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
    required this.authors,
    required this.tags,
    required this.choiceFields,
    required this.booleanFields,
    required this.onChanged,
  });

  final FacetSelections facets;
  final List<DanceForm> forms;
  final List<FormationShape> formations;
  final List<Progression> progressions;
  final List<DanceStatus> statuses;
  final List<Choreographer> authors;
  final List<Tag> tags;
  final List<CustomFieldDef> choiceFields;
  final List<CustomFieldDef> booleanFields;
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
