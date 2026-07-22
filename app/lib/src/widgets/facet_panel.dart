import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../search/collection_query.dart';
import '../search/facet_labels.dart';

/// The one-tap facet filter panel (`docs/design/ux.md` §1). Each section is a
/// multi-select group of [FilterChip]s over the [FacetSelections] the parent
/// owns; toggling a chip mutates that selection and calls [onChanged] so the
/// parent re-runs the search. Within a section selections are OR-ed; sections
/// are AND-ed (see [buildCollectionFilter]).
class FacetPanel extends StatelessWidget {
  const FacetPanel({
    super.key,
    required this.facets,
    required this.forms,
    required this.formations,
    required this.progressions,
    required this.statuses,
    required this.levels,
    required this.hasMixedLevel,
    required this.hasRating,
    required this.authors,
    required this.tags,
    required this.citedSources,
    required this.choiceFields,
    required this.booleanFields,
    required this.textFields,
    required this.numberFields,
    required this.onChanged,
  });

  final FacetSelections facets;
  final List<DanceForm> forms;
  final List<FormationShape> formations;
  final List<Progression> progressions;
  final List<DanceStatus> statuses;
  final List<DanceLevel> levels;
  final bool hasMixedLevel;

  /// Whether any dance carries a star rating; hides the minimum-rating section
  /// for an all-unrated collection.
  final bool hasRating;

  final List<Choreographer> authors;
  final List<Tag> tags;

  /// Published sources cited by at least one dance; drives the Source facet.
  /// Empty hides the section (an uncited collection), mirroring [authors].
  final List<PublishedSource> citedSources;

  final List<CustomFieldDef> choiceFields;
  final List<CustomFieldDef> booleanFields;
  final List<CustomFieldDef> textFields;
  final List<CustomFieldDef> numberFields;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sections = <Widget>[];

    void toggle<T>(Set<T> set, T value, bool selected) {
      selected ? set.add(value) : set.remove(value);
      onChanged();
    }

    if (forms.isNotEmpty) {
      sections.add(
        _FacetSection(
          key: const ValueKey('facet-row-form'),
          label: l10n.collectionFacetType,
          sectionId: 'form',
          activeCount: facets.forms.length,
          chips: [
            for (final f in forms)
              _chip(
                key: 'form-${f.name}',
                label: danceFormLabel(l10n, f),
                icon: Icons.category_outlined,
                selected: facets.forms.contains(f),
                onSelected: (s) => toggle(facets.forms, f, s),
              ),
          ],
        ),
      );
    }

    if (formations.isNotEmpty) {
      sections.add(
        _FacetSection(
          key: const ValueKey('facet-row-formation'),
          label: l10n.collectionFacetFormation,
          sectionId: 'formation',
          activeCount: facets.formations.length,
          chips: [
            for (final shape in formations)
              _chip(
                key: 'formation-${shape.name}',
                label: formationShapeLabel(l10n, shape),
                icon: formationIcon,
                selected: facets.formations.contains(shape),
                onSelected: (s) => toggle(facets.formations, shape, s),
              ),
          ],
        ),
      );
    }

    if (progressions.isNotEmpty) {
      sections.add(
        _FacetSection(
          key: const ValueKey('facet-row-progression'),
          label: l10n.commonProgression,
          sectionId: 'progression',
          activeCount: facets.progressions.length,
          chips: [
            for (final p in progressions)
              _chip(
                key: 'progression-${p.name}',
                label: progressionLabel(l10n, p),
                icon: progressionIcon,
                selected: facets.progressions.contains(p),
                onSelected: (s) => toggle(facets.progressions, p, s),
              ),
          ],
        ),
      );
    }

    if (statuses.isNotEmpty) {
      sections.add(
        _FacetSection(
          key: const ValueKey('facet-row-status'),
          label: l10n.collectionFacetStatus,
          sectionId: 'status',
          activeCount: facets.statuses.length,
          chips: [
            for (final s in statuses)
              _chip(
                key: 'status-${s.name}',
                label: danceStatusLabel(l10n, s),
                icon: Icons.flag_outlined,
                selected: facets.statuses.contains(s),
                onSelected: (sel) => toggle(facets.statuses, s, sel),
              ),
          ],
        ),
      );
    }

    if (levels.isNotEmpty) {
      sections.add(
        _FacetSection(
          key: const ValueKey('facet-row-level'),
          label: l10n.collectionFacetLevel,
          sectionId: 'level',
          activeCount: facets.levels.length,
          chips: [
            for (final l in levels)
              _chip(
                key: 'level-${l.name}',
                label: danceLevelLabel(l10n, l),
                icon: Icons.signal_cellular_alt,
                selected: facets.levels.contains(l),
                onSelected: (sel) => toggle(facets.levels, l, sel),
              ),
          ],
        ),
      );
    }

    if (hasMixedLevel) {
      sections.add(
        _FacetSection(
          key: const ValueKey('facet-row-mixed-level'),
          label: l10n.commonMixedLevel,
          sectionId: 'mixed-level',
          activeCount: facets.mixedLevel == true ? 1 : 0,
          chips: [
            _chip(
              key: 'mixed-level-yes',
              label: l10n.commonMixedLevel,
              icon: Icons.swap_vert,
              selected: facets.mixedLevel == true,
              onSelected: (sel) {
                facets.mixedLevel = sel ? true : null;
                onChanged();
              },
            ),
          ],
        ),
      );
    }

    if (hasRating) {
      sections.add(
        _FacetSection(
          key: const ValueKey('facet-row-min-rating'),
          label: l10n.collectionFacetMinRating,
          sectionId: 'min-rating',
          activeCount: facets.minRating != null ? 1 : 0,
          chips: [
            for (var min = 1; min <= 5; min++)
              _chip(
                key: 'min-rating-$min',
                label: l10n.collectionFacetMinRatingChip(min),
                icon: Icons.star,
                selected: facets.minRating == min,
                // Single-valued floor: selecting sets it, tapping the current
                // selection clears it (removes the RatingFilter).
                onSelected: (sel) {
                  facets.minRating = sel ? min : null;
                  onChanged();
                },
              ),
          ],
        ),
      );
    }

    if (authors.isNotEmpty) {
      // #341: a searchable multi-select replaces the flat per-author chip list,
      // which grew unwieldy as collections accumulate choreographers. Selection
      // still lives in `facets.authorIds`, so filter semantics are unchanged.
      sections.add(
        _AuthorFacet(
          key: const ValueKey('facet-row-author'),
          authors: authors,
          facets: facets,
          onChanged: onChanged,
        ),
      );
    }

    if (tags.isNotEmpty) {
      sections.add(
        _FacetSection(
          key: const ValueKey('facet-row-tags'),
          label: l10n.collectionFacetTags,
          sectionId: 'tags',
          activeCount: facets.tagIds.length,
          chips: [
            for (final t in tags)
              _chip(
                key: 'tag-${t.id}',
                label: t.name,
                icon: Icons.label_outline,
                selected: facets.tagIds.contains(t.id),
                onSelected: (s) => toggle(facets.tagIds, t.id, s),
              ),
          ],
        ),
      );
    }

    if (citedSources.isNotEmpty) {
      sections.add(
        _FacetSection(
          key: const ValueKey('facet-row-source'),
          label: l10n.collectionFacetSource,
          sectionId: 'source',
          activeCount: facets.sourceIds.length,
          chips: [
            for (final s in citedSources)
              _chip(
                key: 'source-${s.id}',
                label: s.title,
                icon: Icons.menu_book_outlined,
                selected: facets.sourceIds.contains(s.id),
                onSelected: (sel) => toggle(facets.sourceIds, s.id, sel),
              ),
          ],
        ),
      );
    }

    for (final def in choiceFields) {
      // Read-only during build: don't create a map entry here (builds must be
      // side-effect free). The entry is created lazily in onSelected.
      final selected = facets.choiceValues[def.id] ?? const <String>{};
      sections.add(
        _FacetSection(
          key: ValueKey('facet-row-cf-choice-${def.id}'),
          label: def.label,
          sectionId: 'cf-choice-${def.id}',
          activeCount: selected.length,
          chips: [
            for (final choice in def.choices ?? const <String>[])
              _chip(
                key: 'cf-${def.id}-$choice',
                label: choice,
                icon: Icons.tune,
                selected: selected.contains(choice),
                onSelected: (s) {
                  final set = facets.choiceValues.putIfAbsent(def.id, () => {});
                  s ? set.add(choice) : set.remove(choice);
                  if (set.isEmpty) facets.choiceValues.remove(def.id);
                  onChanged();
                },
              ),
          ],
        ),
      );
    }

    for (final def in booleanFields) {
      final current = facets.booleanValues[def.id];
      sections.add(
        _FacetSection(
          key: ValueKey('facet-row-cf-bool-${def.id}'),
          label: def.label,
          sectionId: 'cf-bool-${def.id}',
          activeCount: current != null ? 1 : 0,
          chips: [
            _chip(
              key: 'cf-${def.id}-yes',
              label: l10n.commonYes,
              icon: Icons.check,
              selected: current == true,
              onSelected: (s) {
                s
                    ? facets.booleanValues[def.id] = true
                    : facets.booleanValues.remove(def.id);
                onChanged();
              },
            ),
            _chip(
              key: 'cf-${def.id}-no',
              label: l10n.commonNo,
              icon: Icons.close,
              selected: current == false,
              onSelected: (s) {
                s
                    ? facets.booleanValues[def.id] = false
                    : facets.booleanValues.remove(def.id);
                onChanged();
              },
            ),
          ],
        ),
      );
    }

    for (final def in textFields) {
      sections.add(
        _TextFieldFacet(
          key: ValueKey('cf-text-${def.id}'),
          def: def,
          facets: facets,
          onChanged: onChanged,
        ),
      );
    }

    for (final def in numberFields) {
      sections.add(
        _NumberFieldFacet(
          key: ValueKey('cf-num-${def.id}'),
          def: def,
          facets: facets,
          onChanged: onChanged,
        ),
      );
    }

    if (sections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(l10n.collectionFacetNone),
      );
    }

    // The Column's direct children are keyed so Flutter reconciles them by key
    // rather than by position. Without this, conditionally prepending the
    // Clear-filters row (or a change in the visible section set) shifts every
    // following child and remounts the keyed ExpansionTiles, reverting any
    // collapsed section back to its `initiallyExpanded: true` state (#375).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!facets.isEmpty)
          Padding(
            key: const ValueKey('facet-row-clear'),
            padding: const EdgeInsets.only(bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('clear-filters'),
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: Text(l10n.collectionFacetClear),
                onPressed: () {
                  facets.clear();
                  onChanged();
                },
              ),
            ),
          ),
        for (final section in sections)
          Padding(
            key: section.key,
            padding: const EdgeInsets.only(bottom: 8),
            child: section,
          ),
      ],
    );
  }

  Widget _chip({
    required String key,
    required String label,
    required IconData icon,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) => FilterChip(
    key: ValueKey(key),
    label: Text(label),
    avatar: Icon(icon, size: 18),
    selected: selected,
    onSelected: onSelected,
  );
}

class _FacetSection extends StatelessWidget {
  const _FacetSection({
    super.key,
    required this.label,
    required this.chips,
    required this.sectionId,
    this.activeCount = 0,
  });

  final String label;
  final List<Widget> chips;

  /// A stable, unique id for this section (built-in slug or custom-field id).
  /// Distinct from [label], which is user-authored for custom fields and so is
  /// not guaranteed unique across sections.
  final String sectionId;

  /// Number of active selections in this section; drives the count badge.
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    return _FacetExpansion(
      label: label,
      sectionId: sectionId,
      activeCount: activeCount,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(spacing: 8, runSpacing: 4, children: chips),
      ),
    );
  }
}

/// Shared collapsible shell for a facet section: a labelled [ExpansionTile]
/// with a trailing count badge that surfaces how many selections are active in
/// the section (handy in particular once it is collapsed). Starts expanded so
/// keyboard traversal order still matches the visual order and every chip is
/// reachable by default.
class _FacetExpansion extends StatelessWidget {
  const _FacetExpansion({
    required this.label,
    required this.sectionId,
    required this.activeCount,
    required this.child,
  });

  final String label;

  /// Stable, unique key source for the section — never the user-authored label.
  final String sectionId;
  final int activeCount;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      key: ValueKey('facet-section-$sectionId'),
      initiallyExpanded: true,
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Row(
        children: [
          Flexible(child: Text(label, style: theme.textTheme.labelLarge)),
          if (activeCount > 0) ...[
            const SizedBox(width: 8),
            Badge(
              label: Text('$activeCount'),
              backgroundColor: theme.colorScheme.primary,
            ),
          ],
        ],
      ),
      children: [child],
    );
  }
}

/// The Author facet (#341): a searchable multi-select over choreographers.
///
/// Built on the dance-editor name-picker typeahead pattern
/// ([`name_picker.dart`]'s `_AddAutocomplete`) but author-specific and
/// filter-only (no "create" affordance). Type to filter authors; matches are
/// shown in a dropdown and, once chosen, appear as removable chips. Selection
/// is written straight into the parent-owned [FacetSelections.authorIds] set,
/// so the compiled filter (an OR-group of `AuthorFilter` leaves) and the
/// OR-within-facet semantics are identical to the previous chip list. Sits in
/// the shared [_FacetExpansion] shell so the collapsible section and its
/// active-count badge are preserved.
class _AuthorFacet extends StatefulWidget {
  const _AuthorFacet({
    super.key,
    required this.authors,
    required this.facets,
    required this.onChanged,
  });

  final List<Choreographer> authors;
  final FacetSelections facets;
  final VoidCallback onChanged;

  @override
  State<_AuthorFacet> createState() => _AuthorFacetState();
}

class _AuthorFacetState extends State<_AuthorFacet> {
  // Owned here (not by Autocomplete) so a selection can clear the query text,
  // resetting the field for the next author in a multi-select.
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _add(String id) {
    widget.facets.authorIds.add(id);
    _controller.clear();
    widget.onChanged();
  }

  void _remove(String id) {
    widget.facets.authorIds.remove(id);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authorsById = {for (final a in widget.authors) a.id: a.name};
    final selectedIds = widget.facets.authorIds;
    return _FacetExpansion(
      label: l10n.collectionFacetAuthor,
      sectionId: 'author',
      activeCount: selectedIds.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selectedIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final id in selectedIds)
                    InputChip(
                      key: ValueKey('author-facet-chip-$id'),
                      avatar: const Icon(Icons.person_outline, size: 18),
                      label: Text(authorsById[id] ?? id),
                      tooltip: l10n.collectionFacetRemoveAuthor(
                        authorsById[id] ?? id,
                      ),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      deleteButtonTooltipMessage: l10n
                          .collectionFacetRemoveAuthor(authorsById[id] ?? id),
                      onDeleted: () => _remove(id),
                    ),
                ],
              ),
            ),
          Autocomplete<Choreographer>(
            key: const ValueKey('author-facet-autocomplete'),
            textEditingController: _controller,
            focusNode: _focusNode,
            displayStringForOption: (a) => a.name,
            optionsBuilder: (value) {
              final q = value.text.trim().toLowerCase();
              if (q.isEmpty) return const Iterable<Choreographer>.empty();
              // Exclude already-selected authors so the dropdown only offers
              // additions; matching is a case-insensitive substring on name.
              return widget.authors.where(
                (a) =>
                    !selectedIds.contains(a.id) &&
                    a.name.toLowerCase().contains(q),
              );
            },
            onSelected: (a) => _add(a.id),
            fieldViewBuilder: (context, controller, focusNode, onSubmit) {
              return TextField(
                key: const ValueKey('author-facet-search'),
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: l10n.collectionFacetAuthorSearchHint,
                  isDense: true,
                ),
                onSubmitted: (_) => onSubmit(),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 240,
                      maxWidth: 320,
                    ),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        for (final a in options)
                          ListTile(
                            key: ValueKey('author-facet-option-${a.id}'),
                            dense: true,
                            leading: const Icon(Icons.person_outline, size: 18),
                            title: Text(a.name),
                            onTap: () => onSelected(a),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Text custom-field facet: operator chip (contains / equals) + text input.
class _TextFieldFacet extends StatefulWidget {
  const _TextFieldFacet({
    super.key,
    required this.def,
    required this.facets,
    required this.onChanged,
  });

  final CustomFieldDef def;
  final FacetSelections facets;
  final VoidCallback onChanged;

  @override
  State<_TextFieldFacet> createState() => _TextFieldFacetState();
}

class _TextFieldFacetState extends State<_TextFieldFacet> {
  late final TextEditingController _controller;
  CustomFieldOp _op = CustomFieldOp.contains;

  @override
  void initState() {
    super.initState();
    final existing = widget.facets.textValues[widget.def.id];
    _controller = TextEditingController(text: existing?.value ?? '');
    if (existing != null) _op = existing.op;
  }

  @override
  void didUpdateWidget(_TextFieldFacet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync controller when the parent clears the facets (e.g. "Clear all").
    final current = widget.facets.textValues[widget.def.id];
    if (current == null && _controller.text.isNotEmpty) {
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      widget.facets.textValues.remove(widget.def.id);
    } else {
      widget.facets.textValues[widget.def.id] = TextFacetState(
        op: _op,
        value: text,
      );
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active =
        widget.facets.textValues[widget.def.id]?.isEffective ?? false;
    return _FacetExpansion(
      label: widget.def.label,
      sectionId: 'cf-text-${widget.def.id}',
      activeCount: active ? 1 : 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                key: ValueKey('cf-text-${widget.def.id}-contains'),
                label: Text(l10n.collectionFacetOpContains),
                selected: _op == CustomFieldOp.contains,
                onSelected: (_) {
                  setState(() => _op = CustomFieldOp.contains);
                  _commit();
                },
              ),
              FilterChip(
                key: ValueKey('cf-text-${widget.def.id}-equals'),
                label: Text(l10n.collectionFacetOpEquals),
                selected: _op == CustomFieldOp.equals,
                onSelected: (_) {
                  setState(() => _op = CustomFieldOp.equals);
                  _commit();
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            key: ValueKey('cf-text-${widget.def.id}-input'),
            controller: _controller,
            decoration: InputDecoration(
              hintText: l10n.collectionFacetTextHint(widget.def.label),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _controller.clear();
                        _commit();
                        setState(() {});
                      },
                    )
                  : null,
            ),
            onChanged: (_) {
              _commit();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}

/// Number custom-field facet: operator chips (=, <, >, between) + input(s).
class _NumberFieldFacet extends StatefulWidget {
  const _NumberFieldFacet({
    super.key,
    required this.def,
    required this.facets,
    required this.onChanged,
  });

  final CustomFieldDef def;
  final FacetSelections facets;
  final VoidCallback onChanged;

  @override
  State<_NumberFieldFacet> createState() => _NumberFieldFacetState();
}

class _NumberFieldFacetState extends State<_NumberFieldFacet> {
  late final TextEditingController _lo;
  late final TextEditingController _hi;
  CustomFieldOp _op = CustomFieldOp.eq;

  static const _ops = [
    CustomFieldOp.eq,
    CustomFieldOp.lt,
    CustomFieldOp.gt,
    CustomFieldOp.between,
  ];

  String _opLabel(AppLocalizations l10n, CustomFieldOp op) => switch (op) {
    CustomFieldOp.eq => l10n.collectionFacetNumOpEq,
    CustomFieldOp.lt => l10n.collectionFacetNumOpLt,
    CustomFieldOp.gt => l10n.collectionFacetNumOpGt,
    CustomFieldOp.between => l10n.collectionFacetNumOpBetween,
    _ => op.name,
  };

  @override
  void initState() {
    super.initState();
    final existing = widget.facets.numberValues[widget.def.id];
    _lo = TextEditingController(
      text: existing != null ? existing.lo.toString() : '',
    );
    _hi = TextEditingController(text: existing?.hi?.toString() ?? '');
    if (existing != null) _op = existing.op;
  }

  @override
  void didUpdateWidget(_NumberFieldFacet oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget.facets.numberValues[widget.def.id];
    if (current == null) {
      if (_lo.text.isNotEmpty) _lo.clear();
      if (_hi.text.isNotEmpty) _hi.clear();
    }
  }

  @override
  void dispose() {
    _lo.dispose();
    _hi.dispose();
    super.dispose();
  }

  void _commit() {
    final lo = num.tryParse(_lo.text.trim());
    if (lo == null) {
      widget.facets.numberValues.remove(widget.def.id);
      widget.onChanged();
      return;
    }
    if (_op == CustomFieldOp.between) {
      final hi = num.tryParse(_hi.text.trim());
      // Don't fire until the second bound is also valid.
      if (hi == null) {
        widget.facets.numberValues.remove(widget.def.id);
        widget.onChanged();
        return;
      }
      widget.facets.numberValues[widget.def.id] = NumberFacetState(
        op: CustomFieldOp.between,
        lo: lo,
        hi: hi,
      );
    } else {
      widget.facets.numberValues[widget.def.id] = NumberFacetState(
        op: _op,
        lo: lo,
      );
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active =
        widget.facets.numberValues[widget.def.id]?.isEffective ?? false;
    return _FacetExpansion(
      label: widget.def.label,
      sectionId: 'cf-num-${widget.def.id}',
      activeCount: active ? 1 : 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final op in _ops)
                FilterChip(
                  key: ValueKey('cf-num-${widget.def.id}-${op.name}'),
                  label: Text(_opLabel(l10n, op)),
                  selected: _op == op,
                  onSelected: (_) {
                    setState(() => _op = op);
                    _commit();
                  },
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey('cf-num-${widget.def.id}-lo'),
                  controller: _lo,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: InputDecoration(
                    hintText: _op == CustomFieldOp.between
                        ? l10n.collectionFacetNumFrom
                        : l10n.collectionFacetNumValue,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    _commit();
                    setState(() {});
                  },
                ),
              ),
              if (_op == CustomFieldOp.between) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('–'),
                ),
                Expanded(
                  child: TextField(
                    key: ValueKey('cf-num-${widget.def.id}-hi'),
                    controller: _hi,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: InputDecoration(
                      hintText: l10n.collectionFacetNumTo,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      _commit();
                      setState(() {});
                    },
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
