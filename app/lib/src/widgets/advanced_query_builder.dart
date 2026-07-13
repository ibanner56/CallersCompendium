import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../search/collection_query.dart';
import '../search/facet_labels.dart';

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
    required this.sectionLabels,
    required this.onChanged,
  });

  final BuilderGroup root;
  final Taxonomy taxonomy;
  final List<String> sectionLabels;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return _GroupView(
      group: root,
      taxonomy: taxonomy,
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
    required this.sectionLabels,
    required this.onChanged,
    required this.onRemove,
    required this.depth,
  });

  final BuilderGroup group;
  final Taxonomy taxonomy;
  final List<String> sectionLabels;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  label: 'Match',
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
                        DropdownMenuItem(value: kind, child: Text(kind.label)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text('these conditions', style: theme.textTheme.bodySmall),
                const Spacer(),
                if (onRemove != null)
                  IconButton(
                    key: ValueKey('remove-${group.id}'),
                    tooltip: 'Remove group',
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
                  'No conditions yet — add one below.',
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
          sectionLabels: sectionLabels,
          onChanged: onChanged,
          onRemove: remove,
          depth: depth + 1,
        );
      case BuilderFigure():
        return _FigureRow(
          figure: child,
          taxonomy: taxonomy,
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
    return PopupMenuButton<String>(
      key: ValueKey('add-menu-$id'),
      tooltip: 'Add a condition',
      onSelected: (value) => onAdd(switch (value) {
        'figure' => BuilderFigure(),
        'then' => BuilderThen(),
        _ => BuilderGroup(),
      }),
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'figure', child: Text('Has figure')),
        PopupMenuItem(value: 'then', child: Text('Sequence (then)')),
        PopupMenuItem(value: 'group', child: Text('Condition group')),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 18),
            SizedBox(width: 4),
            Text('Add'),
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
    required this.sectionLabels,
    required this.onChanged,
    required this.onRemove,
  });

  final BuilderFigure figure;
  final Taxonomy taxonomy;
  final List<String> sectionLabels;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 12, right: 8),
            child: Text('Has figure'),
          ),
          Expanded(
            child: _FigureEditor(
              figure: figure,
              taxonomy: taxonomy,
              sectionLabels: sectionLabels,
              onChanged: onChanged,
            ),
          ),
          IconButton(
            key: ValueKey('remove-${figure.id}'),
            tooltip: 'Remove figure',
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
    required this.sectionLabels,
    required this.onChanged,
    required this.onRemove,
  });

  final BuilderThen node;
  final Taxonomy taxonomy;
  final List<String> sectionLabels;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('First', style: theme.textTheme.labelSmall),
                _FigureOperandEditor(
                  node: node.before,
                  onReplace: (r) {
                    node.before = r;
                    onChanged();
                  },
                  taxonomy: taxonomy,
                  sectionLabels: sectionLabels,
                  onChanged: onChanged,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('then', style: theme.textTheme.labelMedium),
                ),
                Text('Later', style: theme.textTheme.labelSmall),
                _FigureOperandEditor(
                  node: node.after,
                  onReplace: (r) {
                    node.after = r;
                    onChanged();
                  },
                  taxonomy: taxonomy,
                  sectionLabels: sectionLabels,
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('remove-${node.id}'),
            tooltip: 'Remove sequence',
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
/// [onReplace] is called (and [onChanged] need not be called separately)
/// when the operand type switches between leaf and group.
class _FigureOperandEditor extends StatelessWidget {
  const _FigureOperandEditor({
    required this.node,
    required this.onReplace,
    required this.taxonomy,
    required this.sectionLabels,
    required this.onChanged,
  });

  final BuilderFigureNode node;

  /// Called when the user wants to replace this operand with a different
  /// [BuilderFigureNode] (e.g. wrapping a leaf in a group, or flattening a
  /// single-child group back to a leaf). Already triggers a search update —
  /// the caller must NOT call [onChanged] separately.
  final ValueChanged<BuilderFigureNode> onReplace;

  final Taxonomy taxonomy;
  final List<String> sectionLabels;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => switch (node) {
    final BuilderFigure figure => _buildLeaf(context, figure),
    final BuilderFigureGroup group => _buildGroup(context, group),
  };

  Widget _buildLeaf(BuildContext context, BuilderFigure figure) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FigureEditor(
          figure: figure,
          taxonomy: taxonomy,
          sectionLabels: sectionLabels,
          onChanged: onChanged,
        ),
        TextButton.icon(
          key: ValueKey('group-${figure.id}'),
          onPressed: () => onReplace(BuilderFigureGroup(children: [figure])),
          icon: const Icon(Icons.account_tree_outlined, size: 16),
          label: const Text('Group figures'),
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
    required this.sectionLabels,
    required this.onChanged,
    this.onFlatten,
  });

  final BuilderFigureGroup group;
  final Taxonomy taxonomy;
  final List<String> sectionLabels;
  final VoidCallback onChanged;

  /// When non-null, a "Single figure" button is shown to collapse a
  /// single-leaf group back to a plain [BuilderFigure].
  final VoidCallback? onFlatten;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Semantics(
              label: 'Figure group match',
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
                    DropdownMenuItem(value: kind, child: Text(kind.label)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('of these figures', style: theme.textTheme.bodySmall),
            const Spacer(),
            if (onFlatten != null)
              TextButton(
                key: ValueKey('flatten-${group.id}'),
                onPressed: onFlatten,
                child: const Text('Single figure'),
              ),
          ],
        ),
        for (final child in group.children) _buildChildRow(child),
        TextButton.icon(
          key: ValueKey('add-fig-${group.id}'),
          onPressed: () {
            group.children.add(BuilderFigure());
            onChanged();
          },
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add figure'),
        ),
      ],
    );
  }

  Widget _buildChildRow(BuilderFigureNode child) {
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
                  sectionLabels: sectionLabels,
                  onChanged: onChanged,
                ),
              ),
              IconButton(
                key: ValueKey('remove-fig-${child.id}'),
                tooltip: 'Remove figure',
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
                  sectionLabels: sectionLabels,
                  onChanged: onChanged,
                ),
              ),
              IconButton(
                key: ValueKey('remove-fig-group-${child.id}'),
                tooltip: 'Remove figure group',
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
    required this.sectionLabels,
    required this.onChanged,
  });

  final BuilderFigure figure;
  final Taxonomy taxonomy;
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
                      choices: choices,
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
    return Autocomplete<MoveDef>(
      initialValue: TextEditingValue(text: current),
      displayStringForOption: (m) => m.displayName,
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
        if (figure.move != m.id) {
          figure.move = m.id;
          figure.params.clear();
          onChanged();
        }
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            labelText: 'Move',
            hintText: 'e.g. swing',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (text) {
            // Clearing the field clears the move.
            if (text.trim().isEmpty && figure.move != null) {
              figure.move = null;
              figure.params.clear();
              onChanged();
            }
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
    return Semantics(
      label: 'Section',
      child: DropdownButton<String?>(
        key: ValueKey('section-${figure.id}'),
        value: figure.section,
        hint: const Text('Any section'),
        onChanged: (value) {
          figure.section = value;
          onChanged();
        },
        items: [
          const DropdownMenuItem(value: null, child: Text('Any section')),
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
    required this.choices,
    required this.onChanged,
  });

  final BuilderFigure figure;
  final String paramKey;
  final List<String> choices;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final value = figure.params[paramKey] as String?;
    return Semantics(
      label: paramKey,
      child: DropdownButton<String?>(
        key: ValueKey('param-${figure.id}-$paramKey'),
        value: value,
        hint: Text('Any $paramKey'),
        onChanged: (v) {
          v == null
              ? figure.params.remove(paramKey)
              : figure.params[paramKey] = v;
          onChanged();
        },
        items: [
          DropdownMenuItem(value: null, child: Text('Any $paramKey')),
          for (final choice in choices)
            DropdownMenuItem(value: choice, child: Text(choice)),
        ],
      ),
    );
  }
}
