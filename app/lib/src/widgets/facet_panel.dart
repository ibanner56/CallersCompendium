import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/collection_facets_scope.dart';
import '../search/called_venue_choices.dart';
import '../search/facet_labels.dart';
import '../theme/app_spacing.dart';
import 'calling_history_scopes.dart';
import 'responsive_autocomplete.dart';

/// The one-tap facet filter panel (`docs/design/ux.md` §1). Each section is a
/// multi-select group of [FilterChip]s over the [FacetSelections] the parent
/// owns; toggling a chip mutates that selection and calls [onChanged] so the
/// parent re-runs the search. Within a section selections are OR-ed — except
/// Tunes, which is AND-ed, and Tags, which offers an all / any choice once two
/// tags are selected — and sections are AND-ed (see [buildCollectionFilter]).
///
/// Sections the user hid under Settings → Defaults (#1419, read from
/// [CollectionFacetsScope]) are omitted unless they hold a selection. This is
/// display-only: the parent clears a facet's selection when it becomes hidden.
///
/// A section offers the values the collection has, and **every selected value
/// besides**: a level, author, tag, source, form, meter, custom-field choice
/// or any other value that no dance has any more (or that came in with a saved
/// search before any dance had it) still shows as a selected chip, so a filter
/// that is narrowing the list can always be seen and removed. Such a chip is
/// named from [allLevels], [authorNames], [allTagNames] or [sourceTitles]; an
/// id none of them knows reads "Not in your library". A section the
/// collection would hide (no dance has a mixer, say) shows while it holds a
/// selection.
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
    required this.hasMixer,
    required this.hasRating,
    this.hasCallingHistory = false,
    this.venueChoices,
    required this.authors,
    required this.tags,
    required this.citedSources,
    required this.tunes,
    this.meters = const [],
    this.musicalKeys = const [],
    required this.choiceFields,
    required this.booleanFields,
    required this.textFields,
    required this.numberFields,
    this.allLevels = const [],
    this.authorNames = const {},
    this.allTagNames = const {},
    this.sourceTitles = const {},
    this.allCustomFields = const [],
    this.historyFromSavedSearch = false,
    required this.onChanged,
  });

  final FacetSelections facets;
  final List<DanceForm> forms;
  final List<FormationShape> formations;
  final List<Progression> progressions;
  final List<DanceStatus> statuses;
  final List<DifficultyLevel> levels;
  final bool hasMixedLevel;

  /// Whether any dance is flagged as a mixer; hides the Mixer facet section
  /// when the whole collection has no mixers.
  final bool hasMixer;

  /// Whether any dance carries a star rating; hides the minimum-rating section
  /// for an all-unrated collection.
  final bool hasRating;

  /// Whether any dance has a positive call count in the active history scope.
  final bool hasCallingHistory;

  /// Where the Calling history section's venue chooser reads its rows. Null
  /// leaves the venue row out of the section.
  final VenueChoiceSource? venueChoices;

  final List<Choreographer> authors;
  final List<Tag> tags;

  /// Published sources cited by at least one dance; drives the Source facet.
  /// Empty hides the section (an uncited collection), mirroring [authors].
  final List<PublishedSource> citedSources;

  /// Distinct tune names in the collection, offered as suggestions by the Tunes
  /// facet. Empty hides the section unless a value is already selected: the
  /// field is free text, so an entered value must stay visible (and removable)
  /// even if the dance that supplied the suggestion has since changed.
  final List<String> tunes;

  /// Distinct meters in the collection, offered as chips by the Meter facet.
  /// Empty hides the section unless a meter is already picked.
  final List<String> meters;

  /// Distinct keys in the collection, offered as chips by the Key facet, as
  /// [meters] are by the Meter facet.
  final List<String> musicalKeys;

  final List<CustomFieldDef> choiceFields;
  final List<CustomFieldDef> booleanFields;
  final List<CustomFieldDef> textFields;
  final List<CustomFieldDef> numberFields;

  /// Every configured level, to name a selected level no dance has.
  final List<DifficultyLevel> allLevels;

  /// Every choreographer's name by id, to name a selected author no dance
  /// credits.
  final Map<String, String> authorNames;

  /// Every tag's name by id, to name a selected tag no dance carries.
  final Map<String, String> allTagNames;

  /// Every published source's title by id, to name a selected source no dance
  /// cites.
  final Map<String, String> sourceTitles;

  /// Every custom field, so a selection on one that is not offered as a
  /// filter (not searchable) still has a section.
  final List<CustomFieldDef> allCustomFields;

  /// Whether the panel state came from a saved search, which a **Within**
  /// window outside the presets says ([CallingHistoryScopes]).
  final bool historyFromSavedSearch;

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sections = <Widget>[];

    // Sections the user hid in Settings → Defaults (#1419). A hidden section
    // that still holds a selection is shown anyway: a filter that is narrowing
    // the list must always have a visible control (the detail page's tag chip
    // selects a tag without going through this panel). `suppressed` records
    // that data-backed sections were left out, which picks the empty message.
    final hidden = CollectionFacetsScope.of(context);
    var suppressed = false;
    bool shown(String id) {
      if (!hidden.contains(id) || facets.hasSelectionFor(id)) return true;
      suppressed = true;
      return false;
    }

    void toggle<T>(Set<T> set, T value, bool selected) {
      selected ? set.add(value) : set.remove(value);
      onChanged();
    }

    // The offered values, then every selected one the collection no longer
    // offers, so no selection is left without a chip.
    List<T> withPicked<T>(List<T> offered, Iterable<T> picked) => [
      ...offered,
      for (final p in picked)
        if (!offered.contains(p)) p,
    ];
    final missing = l10n.collectionFacetMissingValue;

    final formValues = withPicked(forms, facets.forms);
    if (formValues.isNotEmpty && shown(CollectionFacetIds.form)) {
      sections.add(
        _FacetSection(
          key: const ValueKey('facet-row-form'),
          label: l10n.collectionFacetType,
          sectionId: 'form',
          activeCount: facets.forms.length,
          chips: [
            for (final f in formValues)
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

    final formationValues = withPicked(formations, facets.formations);
    if (formationValues.isNotEmpty && shown(CollectionFacetIds.formation)) {
      sections.add(
        _FacetSection(
          key: const ValueKey('facet-row-formation'),
          label: l10n.collectionFacetFormation,
          sectionId: 'formation',
          activeCount: facets.formations.length,
          chips: [
            for (final shape in formationValues)
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

    final progressionValues = withPicked(progressions, facets.progressions);
    if (progressionValues.isNotEmpty && shown(CollectionFacetIds.progression)) {
      sections.add(
        _FacetSection(
          key: const ValueKey('facet-row-progression'),
          label: l10n.commonProgression,
          sectionId: 'progression',
          activeCount: facets.progressions.length,
          chips: [
            for (final p in progressionValues)
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

    final statusValues = withPicked(statuses, facets.statuses);
    if (statusValues.isNotEmpty && shown(CollectionFacetIds.status)) {
      sections.add(
        _FacetSection(
          key: const ValueKey('facet-row-status'),
          label: l10n.collectionFacetStatus,
          sectionId: 'status',
          activeCount: facets.statuses.length,
          chips: [
            for (final s in statusValues)
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

    final offeredLevelIds = {for (final l in levels) l.id};
    final levelsById = {for (final l in allLevels) l.id: l};
    final unofferedLevelIds = [
      for (final id in facets.levels)
        if (!offeredLevelIds.contains(id)) id,
    ];
    if ((levels.isNotEmpty || unofferedLevelIds.isNotEmpty) &&
        shown(CollectionFacetIds.level)) {
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
                selected: facets.levels.contains(l.id),
                onSelected: (sel) => toggle(facets.levels, l.id, sel),
              ),
            for (final id in unofferedLevelIds)
              _chip(
                key: 'level-id-$id',
                label: switch (levelsById[id]) {
                  final level? => danceLevelLabel(l10n, level),
                  null => missing,
                },
                icon: Icons.signal_cellular_alt,
                selected: true,
                onSelected: (sel) => toggle(facets.levels, id, sel),
              ),
          ],
        ),
      );
    }

    if ((hasMixedLevel || facets.mixedLevel != null) &&
        shown(CollectionFacetIds.mixedLevel)) {
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
            // The panel offers only "mixed level"; "not mixed level" comes in
            // only with a given panel state, and is shown so it can be seen
            // and removed.
            if (facets.mixedLevel == false)
              _chip(
                key: 'mixed-level-no',
                label: l10n.commonNo,
                icon: Icons.close,
                selected: true,
                onSelected: (sel) {
                  facets.mixedLevel = sel ? false : null;
                  onChanged();
                },
              ),
          ],
        ),
      );
    }

    if ((hasMixer || facets.mixer != null) && shown(CollectionFacetIds.mixer)) {
      sections.add(
        _FacetSection(
          key: const ValueKey('facet-row-mixer'),
          label: l10n.commonMixer,
          sectionId: 'mixer',
          activeCount: facets.mixer == true ? 1 : 0,
          chips: [
            _chip(
              key: 'mixer-yes',
              label: l10n.commonMixer,
              icon: Icons.sync_alt,
              selected: facets.mixer == true,
              onSelected: (sel) {
                facets.mixer = sel ? true : null;
                onChanged();
              },
            ),
            // As for Mixed level above.
            if (facets.mixer == false)
              _chip(
                key: 'mixer-no',
                label: l10n.commonNo,
                icon: Icons.close,
                selected: true,
                onSelected: (sel) {
                  facets.mixer = sel ? false : null;
                  onChanged();
                },
              ),
          ],
        ),
      );
    }

    final minRating = facets.minRating;
    if ((hasRating || minRating != null) &&
        shown(CollectionFacetIds.minRating)) {
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
            if (minRating != null && (minRating < 1 || minRating > 5))
              _chip(
                key: 'min-rating-$minRating',
                label: l10n.collectionFacetMinRatingChip(minRating),
                icon: Icons.star,
                selected: true,
                onSelected: (sel) {
                  facets.minRating = sel ? minRating : null;
                  onChanged();
                },
              ),
          ],
        ),
      );
    }

    if ((hasCallingHistory ||
            facets.hasSelectionFor(CollectionFacetIds.callStatus)) &&
        shown(CollectionFacetIds.callStatus)) {
      sections.add(
        _FacetSection(
          key: const ValueKey('facet-row-call-status'),
          label: l10n.collectionFacetCallStatus,
          sectionId: 'call-status',
          activeCount: facets.callStatuses.length + facets.activeScopeCount,
          chips: [
            _chip(
              key: 'call-status-called',
              label: l10n.collectionFacetCalled,
              icon: Icons.history,
              selected: facets.callStatuses.contains(true),
              onSelected: (s) => toggle(facets.callStatuses, true, s),
            ),
            _chip(
              key: 'call-status-not-called',
              label: l10n.collectionFacetNotCalled,
              icon: Icons.history_toggle_off,
              selected: facets.callStatuses.contains(false),
              onSelected: (s) => toggle(facets.callStatuses, false, s),
            ),
          ],
          footer: CallingHistoryScopes(
            facets: facets,
            venues: venueChoices,
            fromSavedSearch: historyFromSavedSearch,
            onChanged: onChanged,
          ),
        ),
      );
    }

    if ((authors.isNotEmpty || facets.authorIds.isNotEmpty) &&
        shown(CollectionFacetIds.author)) {
      // #341: a searchable multi-select replaces the flat per-author chip list,
      // which grew unwieldy as collections accumulate choreographers. Selection
      // still lives in `facets.authorIds`, so filter semantics are unchanged.
      sections.add(
        _AuthorFacet(
          key: const ValueKey('facet-row-author'),
          authors: authors,
          authorNames: authorNames,
          facets: facets,
          onChanged: onChanged,
        ),
      );
    }

    if ((tunes.isNotEmpty || facets.tunes.isNotEmpty) &&
        shown(CollectionFacetIds.tunes)) {
      sections.add(
        _TunesFacet(
          key: const ValueKey('facet-row-tunes'),
          tunes: tunes,
          facets: facets,
          onChanged: onChanged,
        ),
      );
    }

    // Meter and Key (ADR-006 §9.2, F3): the values the collection has, as
    // chips. A picked value whose last dance changed it stays as a chip, so a
    // filter that is narrowing the list can still be removed.
    void addMusicSection({
      required String id,
      required String label,
      required List<String> offered,
      required Set<String> picked,
      required IconData icon,
    }) {
      // Picks are compared folded, as they match: a pick stays selected when
      // the collection's spelling of it changes ("D minor" to "d minor").
      final pickedFolds = {for (final v in picked) foldForSearch(v)};
      final offeredFolds = {for (final v in offered) foldForSearch(v)};
      final values = [
        ...offered,
        for (final v in picked)
          if (!offeredFolds.contains(foldForSearch(v))) v,
      ];
      void pick(String value, bool selected) {
        final fold = foldForSearch(value);
        picked.removeWhere((v) => foldForSearch(v) == fold);
        if (selected) picked.add(value);
        onChanged();
      }

      if (values.isEmpty || !shown(id)) return;
      sections.add(
        _FacetSection(
          key: ValueKey('facet-row-$id'),
          label: label,
          sectionId: id,
          activeCount: picked.length,
          chips: [
            for (final v in values)
              _chip(
                key: '$id-$v',
                label: v,
                icon: icon,
                selected: pickedFolds.contains(foldForSearch(v)),
                onSelected: (sel) => pick(v, sel),
              ),
          ],
        ),
      );
    }

    addMusicSection(
      id: CollectionFacetIds.meter,
      label: l10n.collectionFacetMeter,
      offered: meters,
      picked: facets.meters,
      icon: Icons.av_timer_outlined,
    );
    addMusicSection(
      id: CollectionFacetIds.musicalKey,
      label: l10n.collectionFacetMusicalKey,
      offered: musicalKeys,
      picked: facets.musicalKeys,
      icon: Icons.music_note_outlined,
    );

    final offeredTagIds = {for (final t in tags) t.id};
    final unofferedTagIds = [
      for (final id in facets.tagIds)
        if (!offeredTagIds.contains(id)) id,
    ];
    if ((tags.isNotEmpty || facets.tagIds.isNotEmpty || facets.untagged) &&
        shown(CollectionFacetIds.tags)) {
      sections.add(
        _FacetSection(
          key: const ValueKey('facet-row-tags'),
          label: l10n.collectionFacetTags,
          sectionId: 'tags',
          activeCount: facets.tagIds.length + (facets.untagged ? 1 : 0),
          chips: [
            // First, so it is not buried in a long alphabetical tag list and
            // cannot be mistaken for a real tag named "Untagged". An OR member of
            // this facet: it neither clears nor is cleared by the tag chips.
            // Its key must stay outside the `tag-` namespace the real chips use
            // below: tag ids are unvalidated (an archive restore keeps whatever
            // id it carries), so `tag-untagged` would collide with a real tag
            // whose id is `untagged`.
            _chip(
              key: 'untagged-chip',
              label: l10n.collectionFacetUntagged,
              icon: Icons.label_off_outlined,
              selected: facets.untagged,
              onSelected: (s) {
                facets.untagged = s;
                onChanged();
              },
            ),
            for (final t in tags)
              _chip(
                key: 'tag-${t.id}',
                label: t.name,
                icon: Icons.label_outline,
                selected: facets.tagIds.contains(t.id),
                onSelected: (s) {
                  facets.setTag(t.id, selected: s);
                  onChanged();
                },
              ),
            // Selected, but carried by no live dance (or deleted): kept, so
            // it can be seen and removed.
            for (final id in unofferedTagIds)
              _chip(
                key: 'tag-$id',
                label: allTagNames[id] ?? missing,
                icon: Icons.label_outline,
                selected: true,
                onSelected: (s) {
                  facets.setTag(id, selected: s);
                  onChanged();
                },
              ),
          ],
          // Below the chips, so it appears where the second tag was just
          // picked without moving any chip.
          footer: facets.tagIds.length > 1
              ? _TagMatchModeToggle(facets: facets, onChanged: onChanged)
              : null,
        ),
      );
    }

    final citedSourceIds = {for (final s in citedSources) s.id};
    final unofferedSourceIds = [
      for (final id in facets.sourceIds)
        if (!citedSourceIds.contains(id)) id,
    ];
    if ((citedSources.isNotEmpty || unofferedSourceIds.isNotEmpty) &&
        shown(CollectionFacetIds.source)) {
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
            for (final id in unofferedSourceIds)
              _chip(
                key: 'source-$id',
                label: sourceTitles[id] ?? missing,
                icon: Icons.menu_book_outlined,
                selected: true,
                onSelected: (sel) => toggle(facets.sourceIds, id, sel),
              ),
          ],
        ),
      );
    }

    // A field not offered as a filter (no longer searchable) still gets its
    // section while it holds a selection, since the search still applies it.
    List<CustomFieldDef> withSelectedFields(
      List<CustomFieldDef> offered,
      CustomFieldType type,
    ) {
      final offeredIds = {for (final d in offered) d.id};
      return [
        ...offered,
        for (final d in allCustomFields)
          if (d.type == type &&
              !offeredIds.contains(d.id) &&
              facets.hasSelectionFor(customFieldFacetId(d.id)))
            d,
      ];
    }

    for (final def in withSelectedFields(
      choiceFields,
      CustomFieldType.choice,
    )) {
      if (!shown(customFieldFacetId(def.id))) continue;
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
            // A selected option the field no longer has stays a chip.
            for (final choice in withPicked(
              def.choices ?? const <String>[],
              selected,
            ))
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

    for (final def in withSelectedFields(
      booleanFields,
      CustomFieldType.boolean,
    )) {
      if (!shown(customFieldFacetId(def.id))) continue;
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

    for (final def in withSelectedFields(textFields, CustomFieldType.text)) {
      if (!shown(customFieldFacetId(def.id))) continue;
      sections.add(
        _TextFieldFacet(
          key: ValueKey('cf-text-${def.id}'),
          def: def,
          facets: facets,
          onChanged: onChanged,
        ),
      );
    }

    for (final def in withSelectedFields(
      numberFields,
      CustomFieldType.number,
    )) {
      if (!shown(customFieldFacetId(def.id))) continue;
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
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(
          suppressed ? l10n.collectionFacetAllHidden : l10n.collectionFacetNone,
        ),
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
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
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
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
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
    this.footer,
  });

  final String label;
  final List<Widget> chips;

  /// A control shown under [chips], if any.
  final Widget? footer;

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
        child: footer == null
            ? Wrap(spacing: 8, runSpacing: 4, children: chips)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 8, runSpacing: 4, children: chips),
                  const SizedBox(height: 8),
                  footer!,
                ],
              ),
      ),
    );
  }
}

/// The Tags section's **All tags / Any tag** choice ([FacetSelections.tagsMatchAll]),
/// shown while two or more tags are selected (FIND-14).
///
/// A [SegmentedButton], so a screen reader announces each segment as a
/// button with its selected state; each segment's tooltip says what it does,
/// and the whole is labelled as the tag-match choice.
class _TagMatchModeToggle extends StatelessWidget {
  const _TagMatchModeToggle({required this.facets, required this.onChanged});

  final FacetSelections facets;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: l10n.collectionFacetTagsMatchLabel,
      child: SegmentedButton<bool>(
        key: const ValueKey('facet-tags-match-mode'),
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: true,
            label: Text(l10n.collectionFacetTagsMatchAll),
            tooltip: l10n.collectionFacetTagsMatchAllTooltip,
          ),
          ButtonSegment(
            value: false,
            label: Text(l10n.collectionFacetTagsMatchAny),
            tooltip: l10n.collectionFacetTagsMatchAnyTooltip,
          ),
        ],
        selected: {facets.tagsMatchAll},
        onSelectionChanged: (selection) {
          facets.tagsMatchAll = selection.single;
          onChanged();
        },
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
      childrenPadding: const EdgeInsets.only(bottom: AppSpacing.xs),
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
/// A type-ahead over [ResponsiveAutocomplete], author-specific and
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
    required this.authorNames,
    required this.facets,
    required this.onChanged,
  });

  final List<Choreographer> authors;

  /// Every choreographer's name by id, for a selected author no dance credits.
  final Map<String, String> authorNames;
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
    // A selected author no dance credits is named from every choreographer,
    // or said to be missing; never shown as a bare id.
    final missing = l10n.collectionFacetMissingValue;
    final authorsById = {
      for (final id in widget.facets.authorIds)
        id: widget.authorNames[id] ?? missing,
      for (final a in widget.authors) a.id: a.name,
    };
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
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
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
          ResponsiveAutocomplete<Choreographer>(
            key: const ValueKey('author-facet-autocomplete'),
            textEditingController: _controller,
            focusNode: _focusNode,
            displayStringForOption: (a) => a.name,
            // Announced when the narrow-layout sheet opens (matches this
            // section's own label, e.g. "Author").
            sheetSemanticLabel: l10n.collectionFacetAuthor,
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
            // Picking always closes the sheet on narrow layouts (owner's Q1
            // decision, uniform across all seven call sites) — even here,
            // where multi-select via repeated adds is the norm. `_add`
            // clears the query so the next search starts empty, but does not
            // refocus: a tap on the field is what reopens the sheet for the
            // next add.
            onSelected: (a) => _add(a.id),
            fieldViewBuilder: (context, controller, focusNode, onSubmit, _) {
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
            optionTileBuilder: (context, a, onSelected) {
              return ListTile(
                key: ValueKey('author-facet-option-${a.id}'),
                dense: true,
                leading: const Icon(Icons.person_outline, size: 18),
                title: Text(a.name),
                onTap: onSelected,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The Tunes facet (#1420): free-text values, each matched as a
/// case-insensitive substring of the dance's tune list, and **all** of them must
/// match ([TunesFilter], AND-within-facet — the opposite of the Author facet).
///
/// Shaped like [_AuthorFacet] — a search field over suggestions, chosen values
/// as removable chips in the shared [_FacetExpansion] shell — with one
/// difference: the vocabulary is only a suggestion list, not a closed set.
/// Tunes are free text, so the first dropdown row is always the typed text
/// itself (`Add "Dmaj"`), which is what Enter commits; without it, Enter would
/// silently pick the first *suggestion* and a value like `Dmaj` could never be
/// entered while `Dmaj / Bmin` existed. Selection is written into the
/// parent-owned [FacetSelections.tunes] via [FacetSelections.addTune].
class _TunesFacet extends StatefulWidget {
  const _TunesFacet({
    super.key,
    required this.tunes,
    required this.facets,
    required this.onChanged,
  });

  final List<String> tunes;
  final FacetSelections facets;
  final VoidCallback onChanged;

  @override
  State<_TunesFacet> createState() => _TunesFacetState();
}

/// One row of the Tunes dropdown: a tune already in the collection, or the
/// text the user typed ([isTyped]).
class _TuneChoice {
  const _TuneChoice(this.value, {this.isTyped = false});

  final String value;
  final bool isTyped;
}

class _TunesFacetState extends State<_TunesFacet> {
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

  void _add(String value) {
    // A refused add (blank, or already a chip) changes nothing, so it must not
    // re-run the search either.
    if (widget.facets.addTune(value)) widget.onChanged();
    _controller.clear();
  }

  void _remove(String value) {
    widget.facets.tunes.remove(value);
    widget.onChanged();
  }

  Iterable<_TuneChoice> _options(TextEditingValue value) {
    final typed = value.text.trim();
    if (typed.isEmpty) return const Iterable<_TuneChoice>.empty();
    final key = typed.toLowerCase();
    final selected = {for (final t in widget.facets.tunes) t.toLowerCase()};
    final matches = [
      for (final t in widget.tunes)
        if (!selected.contains(t.toLowerCase()) &&
            t.toLowerCase().contains(key))
          _TuneChoice(t),
    ];
    // Offer the typed text unless a row (or an existing chip) already says the
    // same thing; it leads so Enter, which takes the first row, commits it.
    final redundant =
        selected.contains(key) ||
        matches.any((m) => m.value.toLowerCase() == key);
    return [if (!redundant) _TuneChoice(typed, isTyped: true), ...matches];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selected = widget.facets.tunes;
    return _FacetExpansion(
      label: l10n.collectionFacetTunes,
      sectionId: 'tunes',
      activeCount: selected.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final tune in selected)
                    InputChip(
                      key: ValueKey('tunes-facet-chip-$tune'),
                      avatar: const Icon(Icons.music_note_outlined, size: 18),
                      label: Text(tune),
                      tooltip: l10n.collectionFacetRemoveTune(tune),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      deleteButtonTooltipMessage: l10n
                          .collectionFacetRemoveTune(tune),
                      onDeleted: () => _remove(tune),
                    ),
                ],
              ),
            ),
          ResponsiveAutocomplete<_TuneChoice>(
            key: const ValueKey('tunes-facet-autocomplete'),
            textEditingController: _controller,
            focusNode: _focusNode,
            displayStringForOption: (c) => c.value,
            sheetSemanticLabel: l10n.collectionFacetTunes,
            // The first row is the typed text; Enter must commit it in the
            // compact sheet too, as `RawAutocomplete` already does inline.
            selectFirstOnSheetSubmit: true,
            optionsBuilder: _options,
            onSelected: (c) => _add(c.value),
            fieldViewBuilder: (context, controller, focusNode, onSubmit, _) {
              return TextField(
                key: const ValueKey('tunes-facet-search'),
                controller: controller,
                focusNode: focusNode,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: l10n.collectionFacetTunesSearchHint,
                  isDense: true,
                ),
                onSubmitted: (_) => onSubmit(),
              );
            },
            optionTileBuilder: (context, c, onSelected) {
              return ListTile(
                key: ValueKey(
                  c.isTyped
                      ? 'tunes-facet-option-typed'
                      : 'tunes-facet-option-${c.value}',
                ),
                dense: true,
                leading: Icon(
                  c.isTyped ? Icons.add : Icons.music_note_outlined,
                  size: 18,
                ),
                title: Text(
                  c.isTyped ? l10n.collectionFacetAddTune(c.value) : c.value,
                ),
                onTap: onSelected,
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

  /// The value the field shows: the one it was opened with, last wrote, or
  /// last took from the parent. Any other value in the facets was set from
  /// outside and is shown instead ([didUpdateWidget]).
  TextFacetState? _shown;

  @override
  void initState() {
    super.initState();
    final existing = widget.facets.textValues[widget.def.id];
    _shown = existing;
    _controller = TextEditingController(text: existing?.value ?? '');
    if (existing != null) _op = existing.op;
  }

  @override
  void didUpdateWidget(_TextFieldFacet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent changed the value: Clear all, or a whole panel state put in
    // place of this one (a saved search). Show the new value, whatever it
    // is, or the field would keep showing the old text while the new one
    // filters. The field's own writes are [_shown] already, so typing is
    // never rewritten under the cursor.
    final current = widget.facets.textValues[widget.def.id];
    if (identical(current, _shown)) return;
    _shown = current;
    final text = current?.value ?? '';
    if (_controller.text != text) _controller.text = text;
    if (current != null) _op = current.op;
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
    _shown = widget.facets.textValues[widget.def.id];
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
                      tooltip: l10n.collectionFacetTextClearTooltip,
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

  /// The value the fields show; see [_TextFieldFacetState._shown].
  NumberFacetState? _shown;

  @override
  void initState() {
    super.initState();
    final existing = widget.facets.numberValues[widget.def.id];
    _shown = existing;
    _lo = TextEditingController(
      text: existing != null ? existing.lo.toString() : '',
    );
    _hi = TextEditingController(text: existing?.hi?.toString() ?? '');
    if (existing != null) _op = existing.op;
  }

  @override
  void didUpdateWidget(_NumberFieldFacet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // As for the text facet: a value the parent set (Clear all, or a whole
    // panel state put in place) is shown, whatever it is; the fields' own
    // writes are not, so a half-typed "-" or a lone lower bound stays.
    final current = widget.facets.numberValues[widget.def.id];
    if (identical(current, _shown)) return;
    _shown = current;
    final lo = current == null ? '' : current.lo.toString();
    final hi = current?.hi?.toString() ?? '';
    if (_lo.text != lo) _lo.text = lo;
    if (_hi.text != hi) _hi.text = hi;
    if (current != null) _op = current.op;
  }

  @override
  void dispose() {
    _lo.dispose();
    _hi.dispose();
    super.dispose();
  }

  void _commit() {
    _write();
    _shown = widget.facets.numberValues[widget.def.id];
    widget.onChanged();
  }

  void _write() {
    final lo = num.tryParse(_lo.text.trim());
    if (lo == null) {
      widget.facets.numberValues.remove(widget.def.id);
      return;
    }
    if (_op == CustomFieldOp.between) {
      final hi = num.tryParse(_hi.text.trim());
      // Don't fire until the second bound is also valid.
      if (hi == null) {
        widget.facets.numberValues.remove(widget.def.id);
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
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
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
