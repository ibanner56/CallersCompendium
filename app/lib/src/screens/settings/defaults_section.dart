// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/active_dialect_scope.dart';
import '../../data/aggressive_beats_update_scope.dart';
import '../../data/collection_facets_scope.dart';
import '../../data/collection_tile_fields_scope.dart';
import '../../data/dance_share_fields_scope.dart';
import '../../data/display_defaults.dart';
import '../../data/persisted_preference.dart';
import '../../data/repositories_scope.dart';
import '../../data/shorthand_mappings_scope.dart';
import '../../diagnostics/error_log.dart';
import '../../editor/figure_draft.dart';
import '../../search/collection_query.dart';
import '../../search/collection_query_labels.dart';
import '../../search/collection_data.dart';
import '../../search/facet_labels.dart';
import '../../search/program_sort.dart';
import '../../search/program_sort_labels.dart';
import '../../theme/app_spacing.dart';
import '../../theme/keyboard_dismiss.dart';
import '../../widgets/figure_list_editor.dart';
import '../../widgets/figure_param_editors.dart';
import '../../widgets/move_autocomplete.dart';
import '../../widgets/collection_picker.dart';
import '../../widgets/section_header.dart';
import '../../widgets/settings_dropdown_row.dart';
import 'default_import_tags_editor.dart';
import 'settings_keys.dart';

/// The Defaults settings section: owns all Display/Program/Dance-authoring
/// default loads, saves, per-setting load-race guards, and text controllers.
class DefaultsSection extends StatefulWidget {
  const DefaultsSection({super.key});

  @override
  State<DefaultsSection> createState() => _DefaultsSectionState();
}

class _DefaultsSectionState extends State<DefaultsSection> {
  /// Default Collection sort order (ROADMAP G.6a), extended to a
  /// [SortDefaultSetting] by issue #895 (ROADMAP G.6c) so "Last used" can be
  /// selected alongside a fixed sort. `null` = not yet loaded; the view shows
  /// `title` (today's default) until the read resolves.
  SortDefaultSetting<CollectionSort>? _defaultCollectionSort;

  /// Default Programs sort order (issue #895, ROADMAP G.6c), mirroring
  /// [_defaultCollectionSort] — Programs had no Settings default before this;
  /// `null` = not yet loaded, shown as `title` until the read resolves.
  SortDefaultSetting<ProgramSort>? _defaultProgramSort;

  bool _defaultsRequested = false;
  // Separate per-setting guards: a user changing one default before its read
  // resolves must not suppress seeding the *other* default from storage.
  bool _defaultSortUserSet = false;
  bool _defaultProgramSortUserSet = false;

  /// Default caller/band for new programs (ROADMAP G.3). Free text seeded once
  /// from storage into these controllers; a late read must not clobber text the
  /// user typed first, so each has its own user-set guard.
  final TextEditingController _defaultProgramCaller = TextEditingController();
  final TextEditingController _defaultProgramBand = TextEditingController();
  bool _defaultCallerUserSet = false;
  bool _defaultBandUserSet = false;

  /// Dance-authoring defaults for NEW dances (ROADMAP DD.1). `null` = not yet
  /// loaded; the view shows today's hardcoded default until the read resolves.
  /// Each has its own user-set guard so a late read can't clobber an in-view
  /// change and one control's change can't suppress seeding the others.
  DanceForm? _defaultDanceForm;
  FormationShape? _defaultDanceFormationShape;
  Progression? _defaultDanceProgression;
  final TextEditingController _defaultDancePhrase = TextEditingController();
  bool _defaultDanceFormUserSet = false;
  bool _defaultDanceFormationShapeUserSet = false;
  bool _defaultDanceProgressionUserSet = false;
  bool _defaultDancePhraseUserSet = false;

  /// Default starting-figures template for NEW dances (ROADMAP DD.2). Held as a
  /// live [FigureDraft] list driving the embedded [FigureListEditor]. Pre-seeded
  /// synchronously with the default `stand_still × 8` so the first frame shows a
  /// sensible template; [_ensureDefaultsLoaded] replaces it with the saved
  /// template unless the user has already edited it (guard below).
  final List<FigureDraft> _defaultDanceFigureDrafts = [
    for (final figure in defaultNewDanceFigureTemplate())
      FigureDraft.fromFigure(figure),
  ];
  bool _defaultDanceFiguresUserSet = false;

  /// Default ordinary side figures for a newly inserted meanwhile container
  /// (issue #1197). Unlike the starting-figures template, an empty list is a
  /// deliberate setting and is therefore preserved as empty.
  final List<FigureDraft> _defaultMeanwhileSideDrafts = [
    for (final figure in defaultMeanwhileSideFigures())
      FigureDraft.fromFigure(figure),
  ];
  bool _defaultMeanwhileSidesUserSet = false;
  final List<FigureDraft> _defaultModifierDrafts = [
    for (final figure in defaultModifierFigures())
      FigureDraft.fromFigure(figure),
  ];
  bool _defaultModifierUserSet = false;

  /// Per-move insert-time parameter overrides (ROADMAP DD.3), keyed by move id
  /// then param key, holding only the params the user overrode (diffs vs the
  /// taxonomy defaults). `_ensureDefaultsLoaded` seeds it from storage unless
  /// the user has already edited it (guard below).
  Map<String, Map<String, Object?>> _defaultMoveParamOverrides = {};

  /// Move ids currently shown in the Move-defaults editor, in view order. Seeded
  /// from the loaded override keys, plus any move the user just added (which has
  /// no diffs yet and therefore persists nothing until a param is changed). Lets
  /// a freshly-added move stay visible before its first override is recorded.
  final List<String> _moveDefaultsShown = [];
  bool _defaultMoveParamOverridesUserSet = false;

  final List<StartingProgramTemplateEntry> _startingProgramTemplate = [];
  bool _startingProgramTemplateUserSet = false;

  /// Dance titles for the starting-program list, from the titles-only
  /// projection (`null` until it resolves, and for good if it failed). The full
  /// [CollectionData] is loaded only when the picker opens.
  Map<String, String>? _danceTitles;
  bool _danceTitlesRequested = false;
  CollectionData? _collectionData;
  Future<CollectionData?>? _collectionDataLoad;

  /// The opt-in "Free-text entry" dance-authoring toggle (issue #419). Defaults
  /// to `false` (off) until the read resolves and on any read failure, so the
  /// feature is strictly opt-in. This value is used only by the starting-figures
  /// editor, which remains in Defaults.
  bool _freeTextEntry = false;

  /// The searchable custom-field definitions, one "Collection filters" checkbox
  /// each (issue #1419) — the same set the Filters panel offers a section for
  /// (`CollectionData.choiceFields` etc.). Loaded once when the section is first
  /// built, so a field created later appears here after Settings is reopened.
  List<CustomFieldDef> _filterFieldDefs = const [];

  /// Lazily loads the persisted Display defaults the first time the Defaults
  /// section is built. Mirrors [_ensureAutoSizeLoaded]: a late read must not
  /// clobber a selection the user made before it resolved (per-setting guards).
  void _ensureDefaultsLoaded(BuildContext context) {
    if (_defaultsRequested) return;
    _defaultsRequested = true;
    final repos = RepositoriesScope.of(context);
    unawaited(
      Future.wait([
        _loadSetting<SortDefaultSetting<CollectionSort>>(
          key: kDefaultCollectionSortKey,
          decode: (stored) => sortDefaultSettingFromStored(
            stored,
            collectionSortFromName,
            CollectionSort.title,
          ),
          userSet: () => _defaultSortUserSet,
          apply: (value) => setState(() => _defaultCollectionSort = value),
          fallback: const SortDefaultSetting.concrete(CollectionSort.title),
        ),
        _loadSetting<SortDefaultSetting<ProgramSort>>(
          key: kDefaultProgramSortKey,
          decode: (stored) => sortDefaultSettingFromStored(
            stored,
            programSortFromName,
            ProgramSort.title,
          ),
          userSet: () => _defaultProgramSortUserSet,
          apply: (value) => setState(() => _defaultProgramSort = value),
          fallback: const SortDefaultSetting.concrete(ProgramSort.title),
        ),
        // A failed read of a free-text default keeps the blank field.
        _loadSetting<String>(
          key: kDefaultProgramCallerKey,
          decode: (stored) => stored is String ? stored.trim() : '',
          userSet: () => _defaultCallerUserSet,
          apply: (value) {
            if (value.isNotEmpty) _defaultProgramCaller.text = value;
          },
        ),
        _loadSetting<String>(
          key: kDefaultProgramBandKey,
          decode: (stored) => stored is String ? stored.trim() : '',
          userSet: () => _defaultBandUserSet,
          apply: (value) {
            if (value.isNotEmpty) _defaultProgramBand.text = value;
          },
        ),
        _loadSetting<DanceForm>(
          key: kDefaultDanceFormKey,
          decode: danceFormFromStored,
          userSet: () => _defaultDanceFormUserSet,
          apply: (value) => setState(() => _defaultDanceForm = value),
          fallback: DanceForm.contra,
        ),
        _loadSetting<FormationShape>(
          key: kDefaultDanceFormationShapeKey,
          decode: formationShapeFromStored,
          userSet: () => _defaultDanceFormationShapeUserSet,
          apply: (value) => setState(() => _defaultDanceFormationShape = value),
          fallback: FormationShape.dupleImproper,
        ),
        _loadSetting<Progression>(
          key: kDefaultDanceProgressionKey,
          decode: progressionFromStored,
          userSet: () => _defaultDanceProgressionUserSet,
          apply: (value) => setState(() => _defaultDanceProgression = value),
          fallback: Progression.single,
        ),
        _loadSetting<String>(
          key: kDefaultDancePhraseStructureKey,
          decode: dancePhraseStructureRawFromStored,
          userSet: () => _defaultDancePhraseUserSet,
          apply: (value) {
            if (value.isNotEmpty) _defaultDancePhrase.text = value;
          },
        ),
        // The three figure templates keep their pre-seeded defaults on a
        // failed read.
        _loadSetting<List<Figure>>(
          key: kDefaultDanceFiguresTemplateKey,
          decode: danceFiguresTemplateFromStored,
          userSet: () => _defaultDanceFiguresUserSet,
          apply: (figures) => setState(() {
            _defaultDanceFigureDrafts
              ..clear()
              ..addAll(figures.map(FigureDraft.fromFigure));
          }),
        ),
        _loadSetting<List<Figure>>(
          key: kDefaultMeanwhileSideFiguresKey,
          decode: meanwhileSideFiguresFromStored,
          userSet: () => _defaultMeanwhileSidesUserSet,
          apply: (figures) => setState(() {
            _defaultMeanwhileSideDrafts
              ..clear()
              ..addAll(figures.map(FigureDraft.fromFigure));
          }),
        ),
        _loadSetting<List<Figure>>(
          key: kDefaultModifierFiguresKey,
          decode: modifierFiguresFromStored,
          userSet: () => _defaultModifierUserSet,
          apply: (figures) => setState(() {
            _defaultModifierDrafts
              ..clear()
              ..addAll(figures.map(FigureDraft.fromFigure));
          }),
        ),
        // A failed read keeps the empty override map (pure taxonomy defaults).
        _loadSetting<Map<String, Map<String, Object?>>>(
          key: kDefaultMoveParamOverridesKey,
          decode: moveParamOverridesFromStored,
          userSet: () => _defaultMoveParamOverridesUserSet,
          apply: (overrides) => setState(() {
            _defaultMoveParamOverrides = overrides;
            // Merge (don't clear): a move the user added before this read
            // resolves isn't persisted yet, so clearing would make it vanish.
            for (final moveId in overrides.keys) {
              if (!_moveDefaultsShown.contains(moveId)) {
                _moveDefaultsShown.add(moveId);
              }
            }
          }),
        ),
        // Not a settings key, but the same guarded shape: a failed read offers
        // no custom-field filter checkboxes.
        _guardedRead<List<CustomFieldDef>, List<CustomFieldDef>>(
          read: repos.customFieldDefs.listAll,
          decode: (defs) => [
            for (final def in defs)
              if (def.searchable) def,
          ],
          apply: (defs) => setState(() => _filterFieldDefs = defs),
        ),
        _loadSetting<bool>(
          key: kFreeTextEntryKey,
          decode: (stored) => stored is bool ? stored : false,
          apply: (value) => setState(() => _freeTextEntry = value),
          fallback: false,
        ),
        // A failed read keeps the empty starting-program template.
        _loadSetting<List<StartingProgramTemplateEntry>>(
          key: kDefaultStartingProgramKey,
          decode: startingProgramTemplateFromStored,
          userSet: () => _startingProgramTemplateUserSet,
          apply: (entries) => setState(() {
            _startingProgramTemplate
              ..clear()
              ..addAll(entries);
          }),
        ),
      ]),
    );
  }

  /// Reads settings [key] once and hands the decoded value to [apply].
  ///
  /// The read is dropped when the section has gone or when [userSet] reports
  /// that the user edited *this* control first, so a slow read can never
  /// clobber an edit. [userSet] is a per-key callback, never shared: one key's
  /// edit must not suppress another key's read. A failed read applies
  /// [fallback] under the same two guards; with no [fallback] the control keeps
  /// the value it was pre-seeded with.
  Future<void> _loadSetting<T>({
    required String key,
    required T Function(Object?) decode,
    required void Function(T) apply,
    bool Function()? userSet,
    T? fallback,
  }) {
    final settings = RepositoriesScope.of(context).settings;
    return _guardedRead<Object?, T>(
      read: () => settings.get(key),
      decode: decode,
      apply: apply,
      userSet: userSet,
      fallback: fallback,
    );
  }

  /// The one guarded read behind every Defaults control, whether its source is
  /// a settings key or a repository query; see [_loadSetting] for the rules.
  Future<void> _guardedRead<S, T>({
    required Future<S> Function() read,
    required T Function(S) decode,
    required void Function(T) apply,
    bool Function()? userSet,
    T? fallback,
  }) async {
    bool superseded() => !mounted || (userSet?.call() ?? false);
    try {
      final stored = await read();
      if (superseded()) return;
      apply(decode(stored));
    } catch (_) {
      // diagnostics: silent — a failed Defaults read leaves the control on its
      // built-in default (or the supplied fallback); there is nothing to retry.
      if (superseded() || fallback == null) return;
      apply(fallback);
    }
  }

  Future<void> _persistStartingProgramTemplate() async {
    _startingProgramTemplateUserSet = true;
    final repos = RepositoriesScope.of(context);
    await persistSetting(
      repos.settings,
      kDefaultStartingProgramKey,
      encodeStartingProgramTemplate(_startingProgramTemplate),
    );
  }

  /// Loads the dance titles the starting-program list prints, once per section
  /// lifetime. A failure is logged once and not retried: [build] calls this on
  /// every rebuild, so retrying here would reload and re-log each time.
  void _ensureDanceTitlesLoaded(BuildContext context) {
    if (_danceTitlesRequested) return;
    _danceTitlesRequested = true;
    final dances = RepositoriesScope.of(context).dances;
    unawaited(_loadDanceTitles(dances));
  }

  Future<void> _loadDanceTitles(DanceRepository dances) async {
    try {
      final rows = await dances.listIdsAndTitles();
      if (!mounted) return;
      setState(
        () => _danceTitles = {for (final row in rows) row.id: row.title},
      );
    } catch (error, stackTrace) {
      logCaughtError(
        error,
        stackTrace,
        source: 'defaults_section.starting_program_titles',
      );
    }
  }

  /// The full collection snapshot, for the dance picker only — [build] never
  /// calls this. Each explicit tap on "add dance" retries a failed load.
  Future<CollectionData?> _ensureCollectionDataLoaded(
    BuildContext context,
  ) async {
    if (_collectionData != null) return _collectionData;
    final inFlight = _collectionDataLoad;
    if (inFlight != null) return inFlight;
    final repos = RepositoriesScope.of(context);
    final load = () async {
      try {
        final data = await CollectionData.load(repos);
        if (mounted) {
          setState(() {
            _collectionData = data;
            _danceTitles = {
              for (final entry in data.dancesById.entries)
                entry.key: entry.value.title,
            };
          });
        }
        return data;
      } catch (error, stackTrace) {
        logCaughtError(
          error,
          stackTrace,
          source: 'defaults_section.starting_program_picker',
        );
        return null;
      } finally {
        _collectionDataLoad = null;
      }
    }();
    _collectionDataLoad = load;
    return load;
  }

  Future<void> _addStartingProgramDance() async {
    final data = await _ensureCollectionDataLoaded(context);
    if (!mounted || data == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Column(
          children: [
            ListTile(
              title: Text(
                AppLocalizations.of(
                  context,
                ).settingsDefaultsStartingProgramPickerTitle,
              ),
              trailing: IconButton(
                tooltip: AppLocalizations.of(context).commonClose,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ),
            Expanded(
              child: CollectionPicker(
                data: data,
                dialect: ActiveDialectScope.of(context),
                enrichment: SearchEnrichment.empty,
                scrollController: scrollController,
                onAddDance: (danceId) {
                  _startingProgramTemplate.add(
                    StartingProgramTemplateEntry(danceId: danceId),
                  );
                  setState(() {});
                  _persistStartingProgramTemplate();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onDefaultProgramCallerChanged(String value) async {
    _defaultCallerUserSet = true;
    final repos = RepositoriesScope.of(context);
    await persistSetting(
      repos.settings,
      kDefaultProgramCallerKey,
      value.trim(),
    );
  }

  Future<void> _onDefaultProgramBandChanged(String value) async {
    _defaultBandUserSet = true;
    final repos = RepositoriesScope.of(context);
    await persistSetting(repos.settings, kDefaultProgramBandKey, value.trim());
  }

  Future<void> _onDefaultDanceFormChanged(DanceForm value) async {
    setState(() {
      _defaultDanceFormUserSet = true;
      _defaultDanceForm = value;
    });
    final repos = RepositoriesScope.of(context);
    await persistSetting(repos.settings, kDefaultDanceFormKey, value.name);
  }

  Future<void> _onDefaultDanceFormationShapeChanged(
    FormationShape value,
  ) async {
    setState(() {
      _defaultDanceFormationShapeUserSet = true;
      _defaultDanceFormationShape = value;
    });
    final repos = RepositoriesScope.of(context);
    await persistSetting(
      repos.settings,
      kDefaultDanceFormationShapeKey,
      value.name,
    );
  }

  Future<void> _onDefaultDanceProgressionChanged(Progression value) async {
    setState(() {
      _defaultDanceProgressionUserSet = true;
      _defaultDanceProgression = value;
    });
    final repos = RepositoriesScope.of(context);
    await persistSetting(
      repos.settings,
      kDefaultDanceProgressionKey,
      value.name,
    );
  }

  Future<void> _onDefaultDancePhraseChanged(String value) async {
    _defaultDancePhraseUserSet = true;
    final repos = RepositoriesScope.of(context);
    await persistSetting(
      repos.settings,
      kDefaultDancePhraseStructureKey,
      value.trim(),
    );
  }

  /// Persists the current starting-figures template as a `figures_json` string
  /// (ROADMAP DD.2). Marks the setting user-set so a late storage read can't
  /// clobber the in-progress edit. Blank/moveless drafts are filtered out, so
  /// an all-blank template serializes to `'[]'` (an intentional empty template).
  Future<void> _persistDanceFiguresTemplate() async {
    _defaultDanceFiguresUserSet = true;
    final figures = [
      for (final draft in _defaultDanceFigureDrafts) ?draft.toFigure(),
    ];
    final repos = RepositoriesScope.of(context);
    await persistSetting(
      repos.settings,
      kDefaultDanceFiguresTemplateKey,
      encodeFigures(figures),
    );
  }

  /// Persists the ordinary side template used by newly inserted meanwhile
  /// containers. A blank list is intentional and therefore encodes as `[]`.
  Future<void> _persistMeanwhileSideDefaults() async {
    _defaultMeanwhileSidesUserSet = true;
    final figures = [
      for (final draft in _defaultMeanwhileSideDrafts) ?draft.toFigure(),
    ];
    final repos = RepositoriesScope.of(context);
    await persistSetting(
      repos.settings,
      kDefaultMeanwhileSideFiguresKey,
      encodeMeanwhileSideFigures(figures),
    );
  }

  Future<void> _persistModifierDefaults() async {
    _defaultModifierUserSet = true;
    if (_defaultModifierDrafts.isNotEmpty &&
        _defaultModifierDrafts.first.toFigure() == null) {
      return;
    }
    final figures = [
      for (final draft in _defaultModifierDrafts) ?draft.toFigure(),
    ];
    await persistSetting(
      RepositoriesScope.of(context).settings,
      kDefaultModifierFiguresKey,
      encodeModifierFigures(figures),
    );
  }

  void _groupDefaultDanceFigures(FigureDraft draft) {
    final index = _defaultDanceFigureDrafts.indexOf(draft);
    if (index == -1 || index >= _defaultDanceFigureDrafts.length - 1) return;
    final first = _defaultDanceFigureDrafts[index];
    final second = _defaultDanceFigureDrafts[index + 1];
    if (first.isMeanwhileGroup || second.isMeanwhileGroup) return;
    final group = FigureDraft(meanwhileSides: [first, second]);
    group.params['beats'] = first.beats;
    group.beatsTouched = first.beatsTouched;
    setState(() {
      _defaultDanceFigureDrafts
        ..removeAt(index + 1)
        ..removeAt(index)
        ..insert(index, group);
    });
    _persistDanceFiguresTemplate();
  }

  void _collapseDefaultDanceFigures(
    FigureDraft group,
    FigureDraft remainingSide,
  ) {
    final index = _defaultDanceFigureDrafts.indexOf(group);
    if (index == -1) return;
    setState(() => _defaultDanceFigureDrafts[index] = remainingSide);
    _persistDanceFiguresTemplate();
  }

  /// Persists the current per-move param overrides as a JSON string (ROADMAP
  /// DD.3), dropping empty inner maps. Marks the setting user-set so a late
  /// storage read can't clobber the in-progress edit.
  Future<void> _persistMoveParamOverrides() async {
    _defaultMoveParamOverridesUserSet = true;
    final repos = RepositoriesScope.of(context);
    await persistSetting(
      repos.settings,
      kDefaultMoveParamOverridesKey,
      encodeMoveParamOverrides(_defaultMoveParamOverrides),
    );
  }

  /// Adds a move to the Move-defaults editor (ROADMAP DD.3). The move starts
  /// with no diffs (nothing persisted yet); it becomes visible so the user can
  /// tweak its params. A no-op if the move is already shown.
  void _onAddMoveDefault(String moveId) {
    if (_moveDefaultsShown.contains(moveId)) return;
    setState(() => _moveDefaultsShown.add(moveId));
  }

  /// Removes a move's overrides entirely (ROADMAP DD.3) and hides it, then
  /// persists.
  void _onRemoveMoveDefault(String moveId) {
    setState(() {
      _moveDefaultsShown.remove(moveId);
      _defaultMoveParamOverrides.remove(moveId);
    });
    _persistMoveParamOverrides();
  }

  /// Records a per-move param override (ROADMAP DD.3). Diff-based: if [value]
  /// equals the taxonomy default for that param, the key is dropped (falling
  /// back to the taxonomy default); otherwise it is recorded. Persists on
  /// change. The move stays shown even when its last diff is dropped.
  void _onMoveParamOverrideChanged(
    String moveId,
    String paramKey,
    Object? value,
  ) {
    final taxonomyDefault = contraTaxonomy.effectiveParams(
      Figure(move: moveId),
    )[paramKey];
    setState(() {
      final inner = _defaultMoveParamOverrides.putIfAbsent(
        moveId,
        () => <String, Object?>{},
      );
      if (value == taxonomyDefault) {
        inner.remove(paramKey);
        if (inner.isEmpty) _defaultMoveParamOverrides.remove(moveId);
      } else {
        inner[paramKey] = value;
      }
    });
    _persistMoveParamOverrides();
  }

  @override
  void dispose() {
    _defaultProgramCaller.dispose();
    _defaultProgramBand.dispose();
    _defaultDancePhrase.dispose();
    super.dispose();
  }

  Future<void> _onDefaultCollectionSortChanged(
    SortDefaultSetting<CollectionSort> value,
  ) async {
    setState(() {
      _defaultSortUserSet = true;
      _defaultCollectionSort = value;
    });
    final repos = RepositoriesScope.of(context);
    await persistSetting(
      repos.settings,
      kDefaultCollectionSortKey,
      encodeSortDefaultSetting(value),
    );
  }

  Future<void> _onDefaultProgramSortChanged(
    SortDefaultSetting<ProgramSort> value,
  ) async {
    setState(() {
      _defaultProgramSortUserSet = true;
      _defaultProgramSort = value;
    });
    final repos = RepositoriesScope.of(context);
    await persistSetting(
      repos.settings,
      kDefaultProgramSortKey,
      encodeSortDefaultSetting(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureDefaultsLoaded(context);
    _ensureDanceTitlesLoaded(context);
    return _DefaultsView(
      programCallerController: _defaultProgramCaller,
      onDefaultProgramCallerChanged: _onDefaultProgramCallerChanged,
      programBandController: _defaultProgramBand,
      onDefaultProgramBandChanged: _onDefaultProgramBandChanged,
      defaultCollectionSort:
          _defaultCollectionSort ??
          const SortDefaultSetting.concrete(CollectionSort.title),
      onDefaultCollectionSortChanged: _onDefaultCollectionSortChanged,
      defaultProgramSort:
          _defaultProgramSort ??
          const SortDefaultSetting.concrete(ProgramSort.title),
      onDefaultProgramSortChanged: _onDefaultProgramSortChanged,
      startingProgramTemplate: _startingProgramTemplate,
      startingProgramDanceTitles: _danceTitles ?? const {},
      onAddStartingProgramDance: _addStartingProgramDance,
      onAddStartingProgramText: (text) {
        _startingProgramTemplate.add(StartingProgramTemplateEntry(text: text));
        setState(() {});
        _persistStartingProgramTemplate();
      },
      onUpdateStartingProgramText: (index, text) {
        final entry = _startingProgramTemplate[index];
        setState(() {
          _startingProgramTemplate[index] = StartingProgramTemplateEntry(
            danceId: entry.danceId,
            text: text.trim().isEmpty ? null : text.trim(),
          );
        });
        _persistStartingProgramTemplate();
      },
      onRemoveStartingProgramEntry: (index) {
        setState(() => _startingProgramTemplate.removeAt(index));
        _persistStartingProgramTemplate();
      },
      onReorderStartingProgramEntry: (oldIndex, newIndex) {
        setState(() {
          final entry = _startingProgramTemplate.removeAt(oldIndex);
          _startingProgramTemplate.insert(newIndex, entry);
        });
        _persistStartingProgramTemplate();
      },
      onAddStartingProgramBreak: () {
        _startingProgramTemplate.add(
          const StartingProgramTemplateEntry(text: Program.breakSlotText),
        );
        setState(() {});
        _persistStartingProgramTemplate();
      },
      defaultDanceForm: _defaultDanceForm ?? DanceForm.contra,
      onDefaultDanceFormChanged: _onDefaultDanceFormChanged,
      defaultDanceFormationShape:
          _defaultDanceFormationShape ?? FormationShape.dupleImproper,
      onDefaultDanceFormationShapeChanged: _onDefaultDanceFormationShapeChanged,
      defaultDanceProgression: _defaultDanceProgression ?? Progression.single,
      onDefaultDanceProgressionChanged: _onDefaultDanceProgressionChanged,
      dancePhraseController: _defaultDancePhrase,
      onDefaultDancePhraseChanged: _onDefaultDancePhraseChanged,
      freeTextEntry: _freeTextEntry,
      filterFieldDefs: _filterFieldDefs,
      danceFigureTemplateDrafts: _defaultDanceFigureDrafts,
      onDanceFigureTemplateChanged: () {
        setState(() {});
        _persistDanceFiguresTemplate();
      },
      onDanceFigureTemplateAdd: () {
        setState(() => _defaultDanceFigureDrafts.add(FigureDraft()));
        _persistDanceFiguresTemplate();
      },
      onDanceFigureTemplateAddMeanwhile: () {
        final draft = FigureDraft(
          meanwhileSides: [FigureDraft(), FigureDraft()],
        );
        setState(() => _defaultDanceFigureDrafts.add(draft));
        _persistDanceFiguresTemplate();
        return Future.value(draft.id);
      },
      onDanceFigureTemplateAddFreeText: (figures) {
        if (figures.isEmpty) return 0;
        setState(
          () => _defaultDanceFigureDrafts.addAll(
            figures.map(FigureDraft.fromFigure),
          ),
        );
        _persistDanceFiguresTemplate();
        return figures.length;
      },
      onDanceFigureTemplateDelete: (draft) {
        setState(() => _defaultDanceFigureDrafts.remove(draft));
        _persistDanceFiguresTemplate();
      },
      onDanceFigureTemplateDuplicate: (draft) {
        setState(() {
          final index = _defaultDanceFigureDrafts.indexOf(draft);
          if (index == -1) return;
          _defaultDanceFigureDrafts.insert(index + 1, draft.clone());
        });
        _persistDanceFiguresTemplate();
      },
      onDanceFigureTemplateReorder: (oldIndex, newIndex) {
        setState(() {
          final draft = _defaultDanceFigureDrafts.removeAt(oldIndex);
          _defaultDanceFigureDrafts.insert(newIndex, draft);
        });
        _persistDanceFiguresTemplate();
      },
      onDanceFigureTemplateGroup: _groupDefaultDanceFigures,
      onDanceFigureTemplateCollapse: _collapseDefaultDanceFigures,
      meanwhileSideDrafts: _defaultMeanwhileSideDrafts,
      onMeanwhileSideChanged: () {
        setState(() {});
        _persistMeanwhileSideDefaults();
      },
      onMeanwhileSideAdd: () {
        if (_defaultMeanwhileSideDrafts.length >= kMaxMeanwhileSides) return;
        setState(() => _defaultMeanwhileSideDrafts.add(FigureDraft()));
        _persistMeanwhileSideDefaults();
      },
      onMeanwhileSideAddFreeText: (figures) {
        final ordinaryFigures = figures
            .where((figure) => !figure.isContainer)
            .toList();
        if (ordinaryFigures.isEmpty) return 0;
        final remaining =
            kMaxMeanwhileSides - _defaultMeanwhileSideDrafts.length;
        if (remaining <= 0) return 0;
        final accepted = ordinaryFigures.take(remaining).toList();
        setState(
          () => _defaultMeanwhileSideDrafts.addAll(
            accepted.map(FigureDraft.fromFigure),
          ),
        );
        _persistMeanwhileSideDefaults();
        return accepted.length;
      },
      onMeanwhileSideDelete: (draft) {
        setState(() => _defaultMeanwhileSideDrafts.remove(draft));
        _persistMeanwhileSideDefaults();
      },
      onMeanwhileSideDuplicate: (draft) {
        if (_defaultMeanwhileSideDrafts.length >= kMaxMeanwhileSides) return;
        setState(() {
          final index = _defaultMeanwhileSideDrafts.indexOf(draft);
          if (index == -1) return;
          _defaultMeanwhileSideDrafts.insert(index + 1, draft.clone());
        });
        _persistMeanwhileSideDefaults();
      },
      onMeanwhileSideReorder: (oldIndex, newIndex) {
        setState(() {
          final draft = _defaultMeanwhileSideDrafts.removeAt(oldIndex);
          _defaultMeanwhileSideDrafts.insert(newIndex, draft);
        });
        _persistMeanwhileSideDefaults();
      },
      modifierDrafts: _defaultModifierDrafts,
      onModifierChanged: () {
        setState(() {});
        _persistModifierDefaults();
      },
      onModifierAdd: () {
        if (_defaultModifierDrafts.length >= kMaxModifierFigures) return;
        setState(() => _defaultModifierDrafts.add(FigureDraft()));
        _persistModifierDefaults();
      },
      onModifierAddFreeText: (figures) {
        final ordinaryFigures = figures
            .where((figure) => !figure.isContainer)
            .toList();
        if (ordinaryFigures.isEmpty) return 0;
        final remaining = kMaxModifierFigures - _defaultModifierDrafts.length;
        if (remaining <= 0) return 0;
        final accepted = ordinaryFigures.take(remaining).toList();
        setState(
          () => _defaultModifierDrafts.addAll(
            accepted.map(FigureDraft.fromFigure),
          ),
        );
        _persistModifierDefaults();
        return accepted.length;
      },
      onModifierDelete: (draft) {
        setState(() => _defaultModifierDrafts.remove(draft));
        _persistModifierDefaults();
      },
      onModifierDuplicate: (draft) {
        if (_defaultModifierDrafts.length >= kMaxModifierFigures) return;
        setState(() {
          final index = _defaultModifierDrafts.indexOf(draft);
          if (index != -1) {
            _defaultModifierDrafts.insert(index + 1, draft.clone());
          }
        });
        _persistModifierDefaults();
      },
      onModifierReorder: (oldIndex, newIndex) {
        setState(() {
          final draft = _defaultModifierDrafts.removeAt(oldIndex);
          _defaultModifierDrafts.insert(newIndex, draft);
        });
        _persistModifierDefaults();
      },
      moveParamOverrides: _defaultMoveParamOverrides,
      shownMoveDefaults: _moveDefaultsShown,
      onAddMoveDefault: _onAddMoveDefault,
      onRemoveMoveDefault: _onRemoveMoveDefault,
      onMoveParamOverrideChanged: _onMoveParamOverrideChanged,
    );
  }
}

/// Edits the ordered vocabulary used by dance difficulty assignments.
class DifficultyLevelsEditor extends StatefulWidget {
  const DifficultyLevelsEditor({super.key});

  @override
  State<DifficultyLevelsEditor> createState() => _DifficultyLevelsEditorState();
}

class _DifficultyLevelsEditorState extends State<DifficultyLevelsEditor> {
  List<DifficultyLevel> _levels = const [];
  final Map<String, String> _pendingLabels = {};
  final Map<String, TextEditingController> _labelControllers = {};
  bool _loading = true;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      _reload();
    }
  }

  Future<void> _reload() async {
    final levels = await RepositoriesScope.of(
      context,
    ).difficultyLevels.listAll();
    if (!mounted) return;
    final levelIds = {for (final level in levels) level.id};
    for (final entry in _labelControllers.entries.toList()) {
      if (!levelIds.contains(entry.key)) {
        entry.value.dispose();
        _labelControllers.remove(entry.key);
      }
    }
    for (final level in levels) {
      _labelControllers[level.id]?.text = level.label;
    }
    setState(() {
      _levels = levels;
      _loading = false;
    });
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Shows [error] as a localized sentence. A caught exception is logged by its
  /// caller (`logCaughtError`); either way the raw text is never rendered: it
  /// is English and names internal ids (CWE-209). [_delete]'s pre-check passes
  /// a synthesized [DifficultyLevelInUse], which has nothing further to log.
  void _report(Object error) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    String? inUseLabel(DifficultyLevelInUse error) {
      if (error.label != null) return error.label;
      for (final level in _levels) {
        if (level.id == error.id) return level.label;
      }
      return null;
    }

    _say(switch (error) {
      DifficultyLevelLabelEmpty() => l10n.settingsDefaultsDifficultyLevelEmpty,
      DifficultyLevelLabelDuplicate(:final label) =>
        l10n.settingsDefaultsDifficultyLevelDuplicate(label),
      DifficultyLevelInUse() when inUseLabel(error) != null =>
        l10n.settingsDefaultsDifficultyLevelInUse(
          inUseLabel(error)!,
          error.count,
        ),
      _ => l10n.settingsDefaultsDifficultyLevelActionFailed,
    });
  }

  Future<void> _add() async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).commonAdd),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context).danceEditorLevelLabel,
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(AppLocalizations.of(context).commonSave),
          ),
        ],
      ),
    );
    controller.dispose();
    final normalized = label?.trim() ?? '';
    if (!mounted || normalized.isEmpty) return;
    try {
      final created = await RepositoriesScope.of(context).difficultyLevels
          .createCustom(
            label: normalized,
            position:
                _levels.fold(
                  -1,
                  (maximum, level) =>
                      level.position > maximum ? level.position : maximum,
                ) +
                1,
          );
      if (!mounted) return;
      setState(() => _levels = [..._levels, created]);
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'defaults_section._add');
      _report(error);
    }
  }

  Future<void> _rename(DifficultyLevel level, String value) async {
    _pendingLabels.remove(level.id);
    final label = value.trim();
    if (label.isEmpty) {
      _labelControllers[level.id]?.text = level.label;
      _say(AppLocalizations.of(context).settingsDefaultsDifficultyLevelEmpty);
      return;
    }
    if (label == level.label) return;
    try {
      await RepositoriesScope.of(context).difficultyLevels.upsert(
        level.copyWith(label: label),
        localUserEdit: true,
      );
      await _reload();
    } catch (error, stackTrace) {
      _labelControllers[level.id]?.text = level.label;
      logCaughtError(error, stackTrace, source: 'defaults_section._rename');
      _report(error);
    }
  }

  @override
  void dispose() {
    for (final controller in _labelControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _delete(DifficultyLevel level) async {
    try {
      final levels = RepositoriesScope.of(context).difficultyLevels;
      final references = await levels.referenceCount(level.id);
      if (references > 0) {
        _report(
          DifficultyLevelInUse(
            id: level.id,
            count: references,
            label: level.label,
          ),
        );
        return;
      }
      await levels.delete(level.id);
      await _reload();
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'defaults_section._delete');
      _report(error);
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final updated = List<DifficultyLevel>.of(_levels);
    final level = updated.removeAt(oldIndex);
    updated.insert(newIndex, level);
    setState(() => _levels = updated);
    try {
      await RepositoriesScope.of(
        context,
      ).difficultyLevels.reorder(updated.map((level) => level.id).toList());
      await _reload();
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'defaults_section._reorder');
      _report(error);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: LinearProgressIndicator(),
      );
    }
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text(l10n.danceEditorLevelLabel),
          trailing: IconButton(
            key: const ValueKey('difficulty-level-add'),
            tooltip: l10n.commonAdd,
            icon: const Icon(Icons.add),
            onPressed: _add,
          ),
        ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _levels.length,
          onReorderItem: _reorder,
          itemBuilder: (context, index) {
            final level = _levels[index];
            final labelController = _labelControllers.putIfAbsent(
              level.id,
              () => TextEditingController(text: level.label),
            );
            return ListTile(
              key: ValueKey(level.id),
              leading: ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle),
              ),
              title: Focus(
                onFocusChange: (focused) {
                  if (!focused) {
                    _rename(level, _pendingLabels[level.id] ?? level.label);
                  }
                },
                child: TextFormField(
                  key: ValueKey('difficulty-level-label-${level.id}'),
                  controller: labelController,
                  onChanged: (value) => _pendingLabels[level.id] = value,
                  onFieldSubmitted: (value) => _rename(level, value),
                  decoration: const InputDecoration(
                    border: UnderlineInputBorder(),
                  ),
                ),
              ),
              trailing: IconButton(
                key: ValueKey('difficulty-level-delete-${level.id}'),
                tooltip: l10n.commonDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(level),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// The Defaults section: app-wide default values, grouped to mirror the
/// ROADMAP's "Defaults (settings pane)" structure. It populates the
/// **Program defaults** subsection (ROADMAP G.3), the **Display defaults**
/// subsection (ROADMAP G.6), and the sibling **Dance-authoring defaults**
/// subsection (DD.1–DD.3, below Display defaults), each introduced by its own
/// [SectionHeader].
class _DefaultsView extends StatelessWidget {
  const _DefaultsView({
    required this.programCallerController,
    required this.onDefaultProgramCallerChanged,
    required this.programBandController,
    required this.onDefaultProgramBandChanged,
    required this.defaultCollectionSort,
    required this.onDefaultCollectionSortChanged,
    required this.defaultProgramSort,
    required this.onDefaultProgramSortChanged,
    required this.startingProgramTemplate,
    required this.startingProgramDanceTitles,
    required this.onAddStartingProgramDance,
    required this.onAddStartingProgramText,
    required this.onUpdateStartingProgramText,
    required this.onRemoveStartingProgramEntry,
    required this.onReorderStartingProgramEntry,
    required this.onAddStartingProgramBreak,
    required this.defaultDanceForm,
    required this.onDefaultDanceFormChanged,
    required this.defaultDanceFormationShape,
    required this.onDefaultDanceFormationShapeChanged,
    required this.defaultDanceProgression,
    required this.onDefaultDanceProgressionChanged,
    required this.dancePhraseController,
    required this.onDefaultDancePhraseChanged,
    required this.freeTextEntry,
    required this.filterFieldDefs,
    required this.danceFigureTemplateDrafts,
    required this.onDanceFigureTemplateChanged,
    required this.onDanceFigureTemplateAdd,
    required this.onDanceFigureTemplateAddMeanwhile,
    required this.onDanceFigureTemplateAddFreeText,
    required this.onDanceFigureTemplateDelete,
    required this.onDanceFigureTemplateDuplicate,
    required this.onDanceFigureTemplateReorder,
    required this.onDanceFigureTemplateGroup,
    required this.onDanceFigureTemplateCollapse,
    required this.meanwhileSideDrafts,
    required this.onMeanwhileSideChanged,
    required this.onMeanwhileSideAdd,
    required this.onMeanwhileSideAddFreeText,
    required this.onMeanwhileSideDelete,
    required this.onMeanwhileSideDuplicate,
    required this.onMeanwhileSideReorder,
    required this.modifierDrafts,
    required this.onModifierChanged,
    required this.onModifierAdd,
    required this.onModifierAddFreeText,
    required this.onModifierDelete,
    required this.onModifierDuplicate,
    required this.onModifierReorder,
    required this.moveParamOverrides,
    required this.shownMoveDefaults,
    required this.onAddMoveDefault,
    required this.onRemoveMoveDefault,
    required this.onMoveParamOverrideChanged,
  });

  final TextEditingController programCallerController;
  final ValueChanged<String> onDefaultProgramCallerChanged;
  final TextEditingController programBandController;
  final ValueChanged<String> onDefaultProgramBandChanged;
  final SortDefaultSetting<CollectionSort> defaultCollectionSort;
  final ValueChanged<SortDefaultSetting<CollectionSort>>
  onDefaultCollectionSortChanged;
  final SortDefaultSetting<ProgramSort> defaultProgramSort;
  final ValueChanged<SortDefaultSetting<ProgramSort>>
  onDefaultProgramSortChanged;
  final List<StartingProgramTemplateEntry> startingProgramTemplate;
  final Map<String, String> startingProgramDanceTitles;
  final VoidCallback onAddStartingProgramDance;
  final ValueChanged<String> onAddStartingProgramText;
  final void Function(int index, String text) onUpdateStartingProgramText;
  final ValueChanged<int> onRemoveStartingProgramEntry;
  final void Function(int oldIndex, int newIndex) onReorderStartingProgramEntry;
  final VoidCallback onAddStartingProgramBreak;
  final DanceForm defaultDanceForm;
  final ValueChanged<DanceForm> onDefaultDanceFormChanged;
  final FormationShape defaultDanceFormationShape;
  final ValueChanged<FormationShape> onDefaultDanceFormationShapeChanged;
  final Progression defaultDanceProgression;
  final ValueChanged<Progression> onDefaultDanceProgressionChanged;
  final TextEditingController dancePhraseController;
  final ValueChanged<String> onDefaultDancePhraseChanged;

  /// The opt-in "Free-text entry" toggle state + its change handler (#419).
  /// Forwarded to the embedded template [FigureListEditor] so the toggle also
  /// governs the Settings starting-figures editor, keeping the toggle's effect
  /// consistent with the dance editor it sits above.
  final bool freeTextEntry;

  /// The searchable custom fields, one Collection-filters checkbox each.
  final List<CustomFieldDef> filterFieldDefs;

  /// The live draft list backing the starting-figures template editor (ROADMAP
  /// DD.2), plus callbacks mirroring the dance editor's [FigureListEditor]
  /// wiring. Owned by [_DefaultsSectionState]; mutated in the callbacks.
  final List<FigureDraft> danceFigureTemplateDrafts;
  final VoidCallback onDanceFigureTemplateChanged;
  final VoidCallback onDanceFigureTemplateAdd;
  final Future<String?> Function() onDanceFigureTemplateAddMeanwhile;

  /// Inserts the figure(s) parsed from one free-text line into the template
  /// (#419); only used when [freeTextEntry] is on.
  final int Function(List<Figure>) onDanceFigureTemplateAddFreeText;
  final ValueChanged<FigureDraft> onDanceFigureTemplateDelete;
  final ValueChanged<FigureDraft> onDanceFigureTemplateDuplicate;
  final void Function(int oldIndex, int newIndex) onDanceFigureTemplateReorder;
  final ValueChanged<FigureDraft> onDanceFigureTemplateGroup;
  final void Function(FigureDraft, FigureDraft) onDanceFigureTemplateCollapse;

  /// Ordinary side defaults for newly inserted meanwhile containers. This
  /// editor intentionally has no container-insertion callback.
  final List<FigureDraft> meanwhileSideDrafts;
  final VoidCallback onMeanwhileSideChanged;
  final VoidCallback onMeanwhileSideAdd;
  final int Function(List<Figure>) onMeanwhileSideAddFreeText;
  final ValueChanged<FigureDraft> onMeanwhileSideDelete;
  final ValueChanged<FigureDraft> onMeanwhileSideDuplicate;
  final void Function(int oldIndex, int newIndex) onMeanwhileSideReorder;
  final List<FigureDraft> modifierDrafts;
  final VoidCallback onModifierChanged;
  final VoidCallback onModifierAdd;
  final int Function(List<Figure>) onModifierAddFreeText;
  final ValueChanged<FigureDraft> onModifierDelete;
  final ValueChanged<FigureDraft> onModifierDuplicate;
  final void Function(int oldIndex, int newIndex) onModifierReorder;

  /// The per-move param overrides (ROADMAP DD.3), keyed by move id then param
  /// key. Owned by [_DefaultsSectionState]; read-only here.
  final Map<String, Map<String, Object?>> moveParamOverrides;

  /// Move ids currently shown in the Move-defaults editor, in view order.
  final List<String> shownMoveDefaults;

  /// Adds a move to the Move-defaults editor (no diffs yet).
  final ValueChanged<String> onAddMoveDefault;

  /// Removes a move's overrides entirely and hides it.
  final ValueChanged<String> onRemoveMoveDefault;

  /// Records a per-move param change; the screen diffs it against the taxonomy
  /// default (equal ⇒ dropped, else recorded) and persists.
  final void Function(String moveId, String paramKey, Object? value)
  onMoveParamOverrideChanged;

  /// The Collection sort orders offered as a default. Excludes
  /// [CollectionSort.relevance], which is only meaningful for a bare full-text
  /// query and never a sensible saved default.
  static const List<CollectionSort> _collectionSortOptions = [
    CollectionSort.title,
    CollectionSort.author,
    CollectionSort.recentlyAdded,
    CollectionSort.lastCalled,
  ];

  /// The Programs sort orders offered as a default (issue #895); every member
  /// of [ProgramSort] is a sensible fixed default, unlike Collection's
  /// [_collectionSortOptions] (which excludes `relevance`).
  static const List<ProgramSort> _programSortOptions = ProgramSort.values;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sectionTitleStyle = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.primary,
    );
    return ListView(
      keyboardDismissBehavior: kTextEntryKeyboardDismiss,
      children: [
        SectionHeader(title: l10n.settingsDefaultsDisplayHeader),
        SettingsDropdownRow(
          title: Text(l10n.settingsDefaultsSortTitle),
          subtitle: Text(l10n.settingsDefaultsSortSubtitle),
          dropdownBuilder: (expanded) =>
              DropdownButton<SortDefaultSetting<CollectionSort>>(
                isExpanded: expanded,
                key: const ValueKey('defaults-collection-sort'),
                value: defaultCollectionSort,
                onChanged: (value) {
                  if (value != null) onDefaultCollectionSortChanged(value);
                },
                items: [
                  for (final sort in _collectionSortOptions)
                    DropdownMenuItem(
                      value: SortDefaultSetting.concrete(sort),
                      child: Text(collectionSortLabel(l10n, sort)),
                    ),
                  DropdownMenuItem(
                    value: SortDefaultSetting.lastUsed(CollectionSort.title),
                    child: Text(l10n.settingsDefaultsSortLastUsed),
                  ),
                ],
              ),
        ),
        SettingsDropdownRow(
          title: Text(l10n.settingsDefaultsProgramSortTitle),
          subtitle: Text(l10n.settingsDefaultsProgramSortSubtitle),
          dropdownBuilder: (expanded) =>
              DropdownButton<SortDefaultSetting<ProgramSort>>(
                isExpanded: expanded,
                key: const ValueKey('defaults-program-sort'),
                value: defaultProgramSort,
                onChanged: (value) {
                  if (value != null) onDefaultProgramSortChanged(value);
                },
                items: [
                  for (final sort in _programSortOptions)
                    DropdownMenuItem(
                      value: SortDefaultSetting.concrete(sort),
                      child: Text(programSortLabel(l10n, sort)),
                    ),
                  DropdownMenuItem(
                    value: SortDefaultSetting.lastUsed(ProgramSort.title),
                    child: Text(l10n.settingsDefaultsSortLastUsed),
                  ),
                ],
              ),
        ),
        SectionHeader(title: l10n.settingsDefaultsCollectionCardHeader),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Text(
            l10n.settingsDefaultsCollectionCardSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        // Scope-backed: reads from CollectionTileFieldsScope (app root) and
        // writes to both the notifier (live rebuild) and settings (persistence).
        Builder(
          builder: (context) {
            final visibleFields = CollectionTileFieldsScope.of(context);
            Future<void> toggle(CollectionTileField field, bool checked) async {
              // Capture context-dependent objects before the await so
              // use_build_context_synchronously is satisfied.
              final notifier = CollectionTileFieldsScope.notifierOf(context);
              final settings = RepositoriesScope.of(context).settings;
              // Read from notifier.value (current live state) rather than the
              // build-time snapshot so rapid successive taps don't lose earlier
              // toggles before a rebuild has propagated them.
              final updated = Set.of(notifier.value);
              if (checked) {
                updated.add(field);
              } else {
                updated.remove(field);
              }
              notifier.value = updated;
              await persistSetting(
                settings,
                kCollectionTileVisibleFieldsKey,
                updated.map((f) => f.toJson()).toList(),
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  key: const ValueKey('defaults-tile-field-authors'),
                  value: visibleFields.contains(CollectionTileField.authors),
                  onChanged: (v) =>
                      toggle(CollectionTileField.authors, v ?? true),
                  title: Text(l10n.settingsDefaultsCollectionCardAuthors),
                ),
                CheckboxListTile(
                  key: const ValueKey('defaults-tile-field-calledCount'),
                  value: visibleFields.contains(
                    CollectionTileField.calledCount,
                  ),
                  onChanged: (v) =>
                      toggle(CollectionTileField.calledCount, v ?? true),
                  title: Text(l10n.settingsDefaultsCollectionCardCalledCount),
                ),
                CheckboxListTile(
                  key: const ValueKey('defaults-tile-field-formation'),
                  value: visibleFields.contains(CollectionTileField.formation),
                  onChanged: (v) =>
                      toggle(CollectionTileField.formation, v ?? true),
                  title: Text(l10n.settingsDefaultsCollectionCardFormation),
                ),
                CheckboxListTile(
                  key: const ValueKey('defaults-tile-field-status'),
                  value: visibleFields.contains(CollectionTileField.status),
                  onChanged: (v) =>
                      toggle(CollectionTileField.status, v ?? true),
                  title: Text(l10n.settingsDefaultsCollectionCardStatus),
                ),
                CheckboxListTile(
                  key: const ValueKey('defaults-tile-field-level'),
                  value: visibleFields.contains(CollectionTileField.level),
                  onChanged: (v) =>
                      toggle(CollectionTileField.level, v ?? true),
                  title: Text(l10n.settingsDefaultsCollectionCardLevel),
                ),
                CheckboxListTile(
                  key: const ValueKey('defaults-tile-field-rating'),
                  value: visibleFields.contains(CollectionTileField.rating),
                  onChanged: (v) =>
                      toggle(CollectionTileField.rating, v ?? true),
                  title: Text(l10n.settingsDefaultsCollectionCardRating),
                ),
                CheckboxListTile(
                  key: const ValueKey('defaults-tile-field-tags'),
                  value: visibleFields.contains(CollectionTileField.tags),
                  onChanged: (v) => toggle(CollectionTileField.tags, v ?? true),
                  title: Text(l10n.settingsDefaultsCollectionCardTags),
                ),
                CheckboxListTile(
                  key: const ValueKey('defaults-tile-field-customFields'),
                  value: visibleFields.contains(
                    CollectionTileField.customFields,
                  ),
                  onChanged: (v) =>
                      toggle(CollectionTileField.customFields, v ?? true),
                  title: Text(l10n.settingsDefaultsCollectionCardCustomFields),
                ),
              ],
            );
          },
        ),
        SectionHeader(title: l10n.settingsDefaultsShareFieldsHeader),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Text(
            l10n.settingsDefaultsShareFieldsSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        // Scope-backed: reads from DanceShareFieldsScope (app root) and
        // writes to both the notifier (live rebuild) and settings
        // (persistence) — same pattern as the collection-card fields above
        // (issue #1434).
        Builder(
          builder: (context) {
            final shareFields = DanceShareFieldsScope.of(context);
            Future<void> toggleShareField(
              DanceShareField field,
              bool checked,
            ) async {
              final notifier = DanceShareFieldsScope.notifierOf(context);
              final settings = RepositoriesScope.of(context).settings;
              final updated = Set.of(notifier.value);
              if (checked) {
                updated.add(field);
              } else {
                updated.remove(field);
              }
              notifier.value = updated;
              await persistSetting(
                settings,
                kProgramDanceShareFieldsKey,
                updated.map((f) => f.toJson()).toList(),
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  key: const ValueKey('defaults-share-field-authors'),
                  value: shareFields.contains(DanceShareField.authors),
                  onChanged: (v) =>
                      toggleShareField(DanceShareField.authors, v ?? true),
                  title: Text(l10n.settingsDefaultsShareFieldsAuthors),
                ),
                CheckboxListTile(
                  key: const ValueKey('defaults-share-field-formation'),
                  value: shareFields.contains(DanceShareField.formation),
                  onChanged: (v) =>
                      toggleShareField(DanceShareField.formation, v ?? true),
                  title: Text(l10n.settingsDefaultsShareFieldsFormation),
                ),
                CheckboxListTile(
                  key: const ValueKey('defaults-share-field-level'),
                  value: shareFields.contains(DanceShareField.level),
                  onChanged: (v) =>
                      toggleShareField(DanceShareField.level, v ?? true),
                  title: Text(l10n.settingsDefaultsShareFieldsLevel),
                ),
                CheckboxListTile(
                  key: const ValueKey('defaults-share-field-mixer'),
                  value: shareFields.contains(DanceShareField.mixer),
                  onChanged: (v) =>
                      toggleShareField(DanceShareField.mixer, v ?? true),
                  title: Text(l10n.settingsDefaultsShareFieldsMixer),
                ),
                CheckboxListTile(
                  key: const ValueKey('defaults-share-field-status'),
                  value: shareFields.contains(DanceShareField.status),
                  onChanged: (v) =>
                      toggleShareField(DanceShareField.status, v ?? true),
                  title: Text(l10n.settingsDefaultsShareFieldsStatus),
                ),
                CheckboxListTile(
                  key: const ValueKey('defaults-share-field-phraseStructure'),
                  value: shareFields.contains(DanceShareField.phraseStructure),
                  onChanged: (v) => toggleShareField(
                    DanceShareField.phraseStructure,
                    v ?? true,
                  ),
                  title: Text(l10n.settingsDefaultsShareFieldsPhraseStructure),
                ),
                CheckboxListTile(
                  key: const ValueKey('defaults-share-field-callingNotes'),
                  value: shareFields.contains(DanceShareField.callingNotes),
                  onChanged: (v) =>
                      toggleShareField(DanceShareField.callingNotes, v ?? true),
                  title: Text(l10n.settingsDefaultsShareFieldsCallingNotes),
                ),
                CheckboxListTile(
                  key: const ValueKey('defaults-share-field-walkthrough'),
                  value: shareFields.contains(DanceShareField.walkthrough),
                  onChanged: (v) =>
                      toggleShareField(DanceShareField.walkthrough, v ?? true),
                  title: Text(l10n.settingsDefaultsShareFieldsWalkthrough),
                ),
                CheckboxListTile(
                  key: const ValueKey('defaults-share-field-tunes'),
                  value: shareFields.contains(DanceShareField.tunes),
                  onChanged: (v) =>
                      toggleShareField(DanceShareField.tunes, v ?? false),
                  title: Text(l10n.settingsDefaultsShareFieldsTunes),
                ),
              ],
            );
          },
        ),
        SectionHeader(title: l10n.settingsDefaultsCollectionFiltersHeader),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Text(
            l10n.settingsDefaultsCollectionFiltersSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        // Scope-backed like the card fields above, but the stored set is the
        // *hidden* ids: a ticked box means the filter is shown.
        Builder(
          builder: (context) {
            final hidden = CollectionFacetsScope.of(context);
            Future<void> toggle(String id, bool shown) async {
              final notifier = CollectionFacetsScope.notifierOf(context);
              final settings = RepositoriesScope.of(context).settings;
              // Read notifier.value, not the build-time snapshot, so rapid
              // successive taps don't lose earlier toggles.
              final updated = Set.of(notifier.value);
              shown ? updated.remove(id) : updated.add(id);
              notifier.value = updated;
              await persistSetting(
                settings,
                kCollectionHiddenFacetsKey,
                CollectionFacetsScope.encode(updated),
              );
            }

            final builtIns = <(String, String)>[
              (CollectionFacetIds.form, l10n.collectionFacetType),
              (CollectionFacetIds.formation, l10n.collectionFacetFormation),
              (CollectionFacetIds.progression, l10n.commonProgression),
              (CollectionFacetIds.status, l10n.collectionFacetStatus),
              (CollectionFacetIds.level, l10n.collectionFacetLevel),
              (CollectionFacetIds.mixedLevel, l10n.commonMixedLevel),
              (CollectionFacetIds.mixer, l10n.commonMixer),
              (CollectionFacetIds.minRating, l10n.collectionFacetMinRating),
              (CollectionFacetIds.callStatus, l10n.collectionFacetCallStatus),
              (CollectionFacetIds.author, l10n.collectionFacetAuthor),
              (CollectionFacetIds.tunes, l10n.collectionFacetTunes),
              (CollectionFacetIds.tags, l10n.collectionFacetTags),
              (CollectionFacetIds.source, l10n.collectionFacetSource),
            ];
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (id, label) in builtIns)
                  CheckboxListTile(
                    key: ValueKey('defaults-facet-$id'),
                    value: !hidden.contains(id),
                    onChanged: (v) => toggle(id, v ?? true),
                    title: Text(label),
                  ),
                for (final def in filterFieldDefs)
                  CheckboxListTile(
                    key: ValueKey('defaults-facet-cf-${def.id}'),
                    value: !hidden.contains(customFieldFacetId(def.id)),
                    onChanged: (v) =>
                        toggle(customFieldFacetId(def.id), v ?? true),
                    title: Text(def.label),
                  ),
              ],
            );
          },
        ),
        ExpansionTile(
          key: const ValueKey('defaults-program-group'),
          title: Text(
            l10n.settingsDefaultsProgramHeader,
            style: sectionTitleStyle,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xxs,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: TextField(
                key: const ValueKey('defaults-program-caller'),
                controller: programCallerController,
                onChanged: onDefaultProgramCallerChanged,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l10n.settingsDefaultsCallerLabel,
                  helperText: l10n.settingsDefaultsPrefilledHelper,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xxs,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: TextField(
                key: const ValueKey('defaults-program-band'),
                controller: programBandController,
                onChanged: onDefaultProgramBandChanged,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l10n.settingsDefaultsBandLabel,
                  helperText: l10n.settingsDefaultsPrefilledHelper,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            _StartingProgramTemplateEditor(
              entries: startingProgramTemplate,
              danceTitles: startingProgramDanceTitles,
              onAddDance: onAddStartingProgramDance,
              onAddText: onAddStartingProgramText,
              onUpdateText: onUpdateStartingProgramText,
              onAddBreak: onAddStartingProgramBreak,
              onRemove: onRemoveStartingProgramEntry,
              onReorder: onReorderStartingProgramEntry,
            ),
          ],
        ),
        ExpansionTile(
          key: const ValueKey('defaults-import-group'),
          title: Text(
            l10n.settingsDefaultsImportHeader,
            style: sectionTitleStyle,
          ),
          children: const [DefaultImportTagsEditor()],
        ),
        ExpansionTile(
          key: const ValueKey('defaults-authoring-group'),
          title: Text(
            l10n.settingsDefaultsAuthoringHeader,
            style: sectionTitleStyle,
          ),
          children: [
            ExpansionTile(
              key: const ValueKey('defaults-difficulty-levels-section'),
              title: Text(l10n.danceEditorLevelLabel),
              initiallyExpanded: false,
              children: const [DifficultyLevelsEditor()],
            ),
            SettingsDropdownRow(
              title: Text(l10n.settingsDefaultsFormTitle),
              subtitle: Text(l10n.settingsDefaultsFormSubtitle),
              dropdownBuilder: (expanded) => DropdownButton<DanceForm>(
                isExpanded: expanded,
                key: const ValueKey('defaults-dance-form'),
                value: defaultDanceForm,
                onChanged: (value) {
                  if (value != null) onDefaultDanceFormChanged(value);
                },
                items: [
                  for (final form in DanceForm.values)
                    DropdownMenuItem(
                      value: form,
                      child: Text(danceFormLabel(l10n, form)),
                    ),
                ],
              ),
            ),
            SettingsDropdownRow(
              title: Text(l10n.settingsDefaultsFormationTitle),
              subtitle: Text(l10n.settingsDefaultsFormationSubtitle),
              dropdownBuilder: (expanded) => DropdownButton<FormationShape>(
                isExpanded: expanded,
                key: const ValueKey('defaults-dance-formation'),
                value: defaultDanceFormationShape,
                onChanged: (value) {
                  if (value != null) onDefaultDanceFormationShapeChanged(value);
                },
                items: [
                  for (final shape in FormationShape.values)
                    DropdownMenuItem(
                      value: shape,
                      child: Text(formationShapeLabel(l10n, shape)),
                    ),
                ],
              ),
            ),
            SettingsDropdownRow(
              title: Text(l10n.settingsDefaultsProgressionTitle),
              subtitle: Text(l10n.settingsDefaultsProgressionSubtitle),
              dropdownBuilder: (expanded) => DropdownButton<Progression>(
                isExpanded: expanded,
                key: const ValueKey('defaults-dance-progression'),
                value: defaultDanceProgression,
                onChanged: (value) {
                  if (value != null) onDefaultDanceProgressionChanged(value);
                },
                items: [
                  for (final progression in Progression.values)
                    DropdownMenuItem(
                      value: progression,
                      child: Text(progressionLabel(l10n, progression)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: TextField(
                key: const ValueKey('defaults-dance-phrase'),
                controller: dancePhraseController,
                onChanged: onDefaultDancePhraseChanged,
                decoration: InputDecoration(
                  labelText: l10n.settingsDefaultsPhraseLabel,
                  helperText: l10n.settingsDefaultsPhraseHelper,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.xxs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsDefaultsStartingFiguresTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.settingsDefaultsStartingFiguresSubtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: FigureListEditor(
                drafts: danceFigureTemplateDrafts,
                taxonomy: contraTaxonomy,
                phraseStructure: PhraseStructure.standard,
                dialect: ActiveDialectScope.of(context),
                freeTextEntry: freeTextEntry,
                shorthandMappings: ShorthandMappingsScope.maybeOf(
                  context,
                )?.store,
                onChanged: onDanceFigureTemplateChanged,
                onAdd: onDanceFigureTemplateAdd,
                onAddFreeText: onDanceFigureTemplateAddFreeText,
                onDelete: onDanceFigureTemplateDelete,
                onDuplicate: onDanceFigureTemplateDuplicate,
                onReorder: onDanceFigureTemplateReorder,
                onAddMeanwhile: onDanceFigureTemplateAddMeanwhile,
                onGroupWithNext: onDanceFigureTemplateGroup,
                onCollapseMeanwhileGroup: onDanceFigureTemplateCollapse,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xxs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsDefaultsMeanwhileTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.settingsDefaultsMeanwhileSubtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: FigureListEditor(
                drafts: meanwhileSideDrafts,
                taxonomy: contraTaxonomy,
                phraseStructure: PhraseStructure.standard,
                dialect: ActiveDialectScope.of(context),
                freeTextEntry: freeTextEntry,
                shorthandMappings: ShorthandMappingsScope.maybeOf(
                  context,
                )?.store,
                onChanged: onMeanwhileSideChanged,
                onAdd: onMeanwhileSideAdd,
                onAddFreeText: onMeanwhileSideAddFreeText,
                onDelete: onMeanwhileSideDelete,
                onDuplicate: onMeanwhileSideDuplicate,
                onReorder: onMeanwhileSideReorder,
                allowAdding: meanwhileSideDrafts.length < kMaxMeanwhileSides,
                allowDuplicating:
                    meanwhileSideDrafts.length < kMaxMeanwhileSides,
                allowModifierSelection: false,
                showPhraseStructure: false,
                keyPrefix: 'meanwhile-side',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xxs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsDefaultsModifierTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.settingsDefaultsModifierSubtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: FigureListEditor(
                drafts: modifierDrafts,
                taxonomy: contraTaxonomy,
                phraseStructure: PhraseStructure.standard,
                dialect: ActiveDialectScope.of(context),
                freeTextEntry: freeTextEntry,
                shorthandMappings: ShorthandMappingsScope.maybeOf(
                  context,
                )?.store,
                onChanged: onModifierChanged,
                onAdd: onModifierAdd,
                onAddFreeText: onModifierAddFreeText,
                onDelete: onModifierDelete,
                onDuplicate: onModifierDuplicate,
                onReorder: onModifierReorder,
                allowAdding: modifierDrafts.length < kMaxModifierFigures,
                allowDuplicating: modifierDrafts.length < kMaxModifierFigures,
                allowModifierSelection: false,
                showPhraseStructure: false,
                keyPrefix: 'modifier-default',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xxs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsDefaultsMoveDefaultsTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.settingsDefaultsMoveDefaultsSubtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: _MoveDefaultsEditor(
                overrides: moveParamOverrides,
                shownMoveIds: shownMoveDefaults,
                onAddMoveDefault: onAddMoveDefault,
                onRemoveMoveDefault: onRemoveMoveDefault,
                onMoveParamOverrideChanged: onMoveParamOverrideChanged,
              ),
            ),
            Builder(
              builder: (context) {
                final aggressiveBeatsUpdate = AggressiveBeatsUpdateScope.of(
                  context,
                );
                return SwitchListTile(
                  key: const ValueKey('defaults-aggressive-beats-update'),
                  value: aggressiveBeatsUpdate,
                  onChanged: (value) async {
                    AggressiveBeatsUpdateScope.notifierOf(context).value =
                        value;
                    final repos = RepositoriesScope.of(context);
                    await persistSetting(
                      repos.settings,
                      kAggressiveBeatsUpdateKey,
                      value,
                    );
                  },
                  title: Text(l10n.settingsDefaultsAggressiveBeatsUpdateTitle),
                  subtitle: Text(
                    l10n.settingsDefaultsAggressiveBeatsUpdateSubtitle,
                  ),
                  isThreeLine: true,
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _StartingProgramTemplateEditor extends StatefulWidget {
  const _StartingProgramTemplateEditor({
    required this.entries,
    required this.danceTitles,
    required this.onAddDance,
    required this.onAddText,
    required this.onUpdateText,
    required this.onAddBreak,
    required this.onRemove,
    required this.onReorder,
  });

  final List<StartingProgramTemplateEntry> entries;
  final Map<String, String> danceTitles;
  final VoidCallback onAddDance;
  final ValueChanged<String> onAddText;
  final void Function(int index, String text) onUpdateText;
  final VoidCallback onAddBreak;
  final ValueChanged<int> onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  State<_StartingProgramTemplateEditor> createState() =>
      _StartingProgramTemplateEditorState();
}

class _StartingProgramTemplateEditorState
    extends State<_StartingProgramTemplateEditor> {
  final _textController = TextEditingController();
  late List<Object> _entryKeys;

  @override
  void initState() {
    super.initState();
    _entryKeys = List<Object>.generate(widget.entries.length, (_) => Object());
  }

  @override
  void didUpdateWidget(covariant _StartingProgramTemplateEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_entryKeys.length < widget.entries.length) {
      _entryKeys.addAll(
        List<Object>.generate(
          widget.entries.length - _entryKeys.length,
          (_) => Object(),
        ),
      );
    } else if (_entryKeys.length > widget.entries.length) {
      _entryKeys = _entryKeys.sublist(0, widget.entries.length);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsDefaultsStartingProgramTitle),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.settingsDefaultsStartingProgramSubtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (var index = 0; index < widget.entries.length; index++)
            Builder(
              builder: (context) {
                final entry = widget.entries[index];
                return ListTile(
                  key: ValueKey(
                    'starting-program-note-${identityHashCode(_entryKeys[index])}',
                  ),
                  dense: true,
                  title: Text(
                    entry.danceId == null
                        ? entry.text ?? ''
                        : widget.danceTitles[entry.danceId] ??
                              l10n.settingsDefaultsStartingProgramUnavailableDance(
                                entry.danceId!,
                              ),
                  ),
                  subtitle: entry.danceId == null
                      ? null
                      : TextFormField(
                          key: ValueKey(_entryKeys[index]),
                          initialValue: entry.text ?? '',
                          decoration: InputDecoration(
                            labelText:
                                l10n.settingsDefaultsStartingProgramNoteLabel,
                          ),
                          onChanged: (value) =>
                              widget.onUpdateText(index, value.trim()),
                        ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: l10n.settingsDefaultsStartingProgramMoveUp,
                        icon: const Icon(Icons.arrow_upward),
                        onPressed: index == 0
                            ? null
                            : () {
                                setState(() {
                                  final key = _entryKeys.removeAt(index);
                                  _entryKeys.insert(index - 1, key);
                                });
                                widget.onReorder(index, index - 1);
                              },
                      ),
                      IconButton(
                        tooltip: l10n.settingsDefaultsStartingProgramMoveDown,
                        icon: const Icon(Icons.arrow_downward),
                        onPressed: index == widget.entries.length - 1
                            ? null
                            : () {
                                setState(() {
                                  final key = _entryKeys.removeAt(index);
                                  _entryKeys.insert(index + 1, key);
                                });
                                widget.onReorder(index, index + 1);
                              },
                      ),
                      IconButton(
                        tooltip: l10n.commonDelete,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          setState(() => _entryKeys.removeAt(index));
                          widget.onRemove(index);
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('starting-program-add-dance'),
                onPressed: widget.onAddDance,
                icon: const Icon(Icons.library_music_outlined),
                label: Text(l10n.programsAddDanceButton),
              ),
              OutlinedButton.icon(
                key: const ValueKey('starting-program-add-text'),
                onPressed: () {
                  final text = _textController.text.trim();
                  if (text.isEmpty) return;
                  widget.onAddText(text);
                  _textController.clear();
                },
                icon: const Icon(Icons.notes_outlined),
                label: Text(l10n.programsAddNoteBreakButton),
              ),
              OutlinedButton.icon(
                key: const ValueKey('starting-program-insert-break'),
                onPressed: widget.onAddBreak,
                icon: const Icon(Icons.free_breakfast_outlined),
                label: Text(l10n.programsInsertBreakButton),
              ),
            ],
          ),
          TextField(
            controller: _textController,
            decoration: InputDecoration(
              labelText: l10n.settingsDefaultsStartingProgramTextLabel,
            ),
          ),
        ],
      ),
    );
  }
}

/// The Move-defaults editor (ROADMAP DD.3): a list of configured per-move
/// parameter overrides, each with its move name, a remove control, and the
/// move's parameters rendered via [FigureParamEditor] (seeded from the current
/// override else the taxonomy default). An "Add move default" affordance opens
/// a [MoveAutocomplete] picker. Recording/dropping diffs and persistence are
/// handled by the owning [_DefaultsSectionState] via the callbacks; this widget
/// only renders and reports edits (the add-move dialog is its only local UI
/// state, shown transiently via [showDialog]).
class _MoveDefaultsEditor extends StatelessWidget {
  const _MoveDefaultsEditor({
    required this.overrides,
    required this.shownMoveIds,
    required this.onAddMoveDefault,
    required this.onRemoveMoveDefault,
    required this.onMoveParamOverrideChanged,
  });

  final Map<String, Map<String, Object?>> overrides;
  final List<String> shownMoveIds;
  final ValueChanged<String> onAddMoveDefault;
  final ValueChanged<String> onRemoveMoveDefault;
  final void Function(String moveId, String paramKey, Object? value)
  onMoveParamOverrideChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dialect = ActiveDialectScope.of(context);
    final renderer = FigureRenderer(contraTaxonomy);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final moveId in shownMoveIds)
          _buildMoveCard(context, moveId, dialect, renderer),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: OutlinedButton.icon(
              key: const ValueKey('move-defaults-add'),
              icon: const Icon(Icons.add),
              label: Text(l10n.settingsDefaultsAddMoveButton),
              onPressed: () => _openAddMoveDialog(context, dialect),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMoveCard(
    BuildContext context,
    String moveId,
    Dialect dialect,
    FigureRenderer renderer,
  ) {
    final l10n = AppLocalizations.of(context);
    final def = contraTaxonomy.resolve(moveId);
    final displayName = def == null
        ? moveId
        : renderer.displayMoveName(moveId, dialect);
    // Effective params include the taxonomy defaults; overlay any saved
    // override so the editor shows the value the user will actually get.
    final effective = def == null
        ? const <String, Object?>{}
        : contraTaxonomy.effectiveParams(Figure(move: moveId));
    final moveOverrides = overrides[moveId] ?? const <String, Object?>{};
    return Card(
      key: ValueKey('move-default-card-$moveId'),
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.xs,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    displayName,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: ValueKey('move-default-remove-$moveId'),
                  tooltip: l10n.settingsDefaultsRemoveMoveTooltip,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onRemoveMoveDefault(moveId),
                ),
              ],
            ),
            if (def == null)
              Text(
                l10n.settingsDefaultsMoveGone,
                style: Theme.of(context).textTheme.bodySmall,
              )
            else if (def.params.isEmpty)
              Text(
                l10n.settingsDefaultsMoveNoParams,
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final entry in def.params.entries)
                    FigureParamEditor(
                      key: ValueKey('move-default-$moveId-${entry.key}'),
                      keyPrefix: 'move-default-$moveId',
                      paramKey: entry.key,
                      spec: entry.value,
                      value: moveOverrides.containsKey(entry.key)
                          ? moveOverrides[entry.key]
                          : effective[entry.key],
                      onChanged: (v) =>
                          onMoveParamOverrideChanged(moveId, entry.key, v),
                      dialect: dialect,
                      moveId: moveId,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddMoveDialog(BuildContext context, Dialect dialect) async {
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.settingsDefaultsAddMoveButton),
          content: SizedBox(
            width: 320,
            child: MoveAutocomplete(
              key: const ValueKey('move-defaults-add-picker'),
              fieldKey: 'move-defaults-add-picker',
              taxonomy: contraTaxonomy,
              dialect: dialect,
              initialText: '',
              includeAliases: false,
              autofocus: true,
              onSelected: (option) {
                onAddMoveDefault(option.id);
                Navigator.of(dialogContext).pop();
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.commonCancel),
            ),
          ],
        );
      },
    );
  }
}
