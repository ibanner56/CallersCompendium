import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../models/dance_list_entry.dart' show formationShapeLabel;
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
    required this.authors,
    required this.tags,
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
  final List<Choreographer> authors;
  final List<Tag> tags;
  final List<CustomFieldDef> choiceFields;
  final List<CustomFieldDef> booleanFields;
  final List<CustomFieldDef> textFields;
  final List<CustomFieldDef> numberFields;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[];

    void toggle<T>(Set<T> set, T value, bool selected) {
      selected ? set.add(value) : set.remove(value);
      onChanged();
    }

    if (forms.isNotEmpty) {
      sections.add(
        _FacetSection(
          label: 'Type',
          chips: [
            for (final f in forms)
              _chip(
                key: 'form-${f.name}',
                label: danceFormLabel(f),
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
          label: 'Formation',
          chips: [
            for (final shape in formations)
              _chip(
                key: 'formation-${shape.name}',
                label: formationShapeLabel(shape),
                icon: Icons.grid_view,
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
          label: 'Progression',
          chips: [
            for (final p in progressions)
              _chip(
                key: 'progression-${p.name}',
                label: progressionLabel(p),
                icon: Icons.trending_flat,
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
          label: 'Status',
          chips: [
            for (final s in statuses)
              _chip(
                key: 'status-${s.name}',
                label: danceStatusLabel(s),
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
          label: 'Level',
          chips: [
            for (final l in levels)
              _chip(
                key: 'level-${l.name}',
                label: danceLevelLabel(l),
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
          label: 'Mixed level',
          chips: [
            _chip(
              key: 'mixed-level-yes',
              label: 'Mixed level',
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

    if (authors.isNotEmpty) {
      sections.add(
        _FacetSection(
          label: 'Author',
          chips: [
            for (final a in authors)
              _chip(
                key: 'author-${a.id}',
                label: a.name,
                icon: Icons.person_outline,
                selected: facets.authorIds.contains(a.id),
                onSelected: (s) => toggle(facets.authorIds, a.id, s),
              ),
          ],
        ),
      );
    }

    if (tags.isNotEmpty) {
      sections.add(
        _FacetSection(
          label: 'Tags',
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

    for (final def in choiceFields) {
      // Read-only during build: don't create a map entry here (builds must be
      // side-effect free). The entry is created lazily in onSelected.
      final selected = facets.choiceValues[def.id] ?? const <String>{};
      sections.add(
        _FacetSection(
          label: def.label,
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
          label: def.label,
          chips: [
            _chip(
              key: 'cf-${def.id}-yes',
              label: 'Yes',
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
              label: 'No',
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
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No filters available for this collection yet.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in sections)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: section),
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
  const _FacetSection({required this.label, required this.chips});

  final String label;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 4, children: chips),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.def.label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              key: ValueKey('cf-text-${widget.def.id}-contains'),
              label: const Text('contains'),
              selected: _op == CustomFieldOp.contains,
              onSelected: (_) {
                setState(() => _op = CustomFieldOp.contains);
                _commit();
              },
            ),
            FilterChip(
              key: ValueKey('cf-text-${widget.def.id}-equals'),
              label: const Text('equals'),
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
            hintText: 'Filter by ${widget.def.label}…',
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
    (op: CustomFieldOp.eq, label: '='),
    (op: CustomFieldOp.lt, label: '<'),
    (op: CustomFieldOp.gt, label: '>'),
    (op: CustomFieldOp.between, label: 'between'),
  ];

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.def.label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in _ops)
              FilterChip(
                key: ValueKey('cf-num-${widget.def.id}-${entry.op.name}'),
                label: Text(entry.label),
                selected: _op == entry.op,
                onSelected: (_) {
                  setState(() => _op = entry.op);
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
                  hintText: _op == CustomFieldOp.between ? 'From' : 'Value',
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
                  decoration: const InputDecoration(
                    hintText: 'To',
                    isDense: true,
                    border: OutlineInputBorder(),
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
    );
  }
}
