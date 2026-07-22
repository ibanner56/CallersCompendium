// Part of the Settings screen, split by section (Stage-7 item 7.2).
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../data/active_dialect_scope.dart';
import '../../data/display_defaults.dart';
import '../../data/repositories_scope.dart';
import '../../data/shorthand_mappings_scope.dart';
import '../../editor/figure_draft.dart';
import '../../search/collection_query.dart';
import '../../search/collection_query_labels.dart';
import '../../search/facet_labels.dart';
import '../../theme/app_spacing.dart';
import '../../theme/keyboard_dismiss.dart';
import '../../widgets/figure_list_editor.dart';
import '../../widgets/figure_param_editors.dart';
import '../../widgets/move_autocomplete.dart';
import '../../widgets/section_header.dart';
import '../shorthand_mappings_screen.dart';
import 'settings_keys.dart';

/// The Defaults settings section: owns all Display/Program/Dance-authoring
/// default loads, saves, per-setting load-race guards, and text controllers.
class DefaultsSection extends StatefulWidget {
  const DefaultsSection({super.key});

  @override
  State<DefaultsSection> createState() => _DefaultsSectionState();
}

class _DefaultsSectionState extends State<DefaultsSection> {
  /// Default Collection sort order (ROADMAP G.6a). `null` = not yet loaded;
  /// the view shows `title` (today's default) until the read resolves.
  CollectionSort? _defaultCollectionSort;

  /// Default dance-detail rendering (ROADMAP G.6b). `null` = not yet loaded;
  /// the view shows active-dialect (today's default) until the read resolves.
  DanceDetailRendering? _defaultDanceDetailRendering;
  bool _defaultsRequested = false;
  // Separate per-setting guards: a user changing one default before its read
  // resolves must not suppress seeding the *other* default from storage.
  bool _defaultSortUserSet = false;
  bool _defaultRenderingUserSet = false;

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

  /// The opt-in "Free-text entry" dance-authoring toggle (issue #419). Defaults
  /// to `false` (off) until the read resolves and on any read failure, so the
  /// feature is strictly opt-in. A late storage read must not clobber a toggle
  /// the user flipped first, hence its own user-set guard.
  bool _freeTextEntry = false;
  bool _freeTextEntryUserSet = false;

  /// Lazily loads the persisted Display defaults the first time the Defaults
  /// section is built. Mirrors [_ensureAutoSizeLoaded]: a late read must not
  /// clobber a selection the user made before it resolved (per-setting guards).
  void _ensureDefaultsLoaded(BuildContext context) {
    if (_defaultsRequested) return;
    _defaultsRequested = true;
    final repos = RepositoriesScope.of(context);
    repos.settings
        .get(kDefaultCollectionSortKey)
        .then((stored) {
          if (!mounted || _defaultSortUserSet) return;
          setState(() {
            _defaultCollectionSort =
                collectionSortFromName(stored) ?? CollectionSort.title;
          });
        })
        .catchError((_) {
          if (!mounted || _defaultSortUserSet) return;
          setState(() => _defaultCollectionSort = CollectionSort.title);
        });
    repos.settings
        .get(kDefaultDanceDetailRenderingKey)
        .then((stored) {
          if (!mounted || _defaultRenderingUserSet) return;
          setState(() {
            _defaultDanceDetailRendering = danceDetailRenderingFromStored(
              stored,
            );
          });
        })
        .catchError((_) {
          if (!mounted || _defaultRenderingUserSet) return;
          setState(
            () => _defaultDanceDetailRendering =
                DanceDetailRendering.activeDialect,
          );
        });
    repos.settings
        .get(kDefaultProgramCallerKey)
        .then((stored) {
          if (!mounted || _defaultCallerUserSet) return;
          final value = stored is String ? stored.trim() : '';
          if (value.isNotEmpty) {
            _defaultProgramCaller.text = value;
          }
        })
        .catchError((_) {
          /* fall back to a blank caller field */
        });
    repos.settings
        .get(kDefaultProgramBandKey)
        .then((stored) {
          if (!mounted || _defaultBandUserSet) return;
          final value = stored is String ? stored.trim() : '';
          if (value.isNotEmpty) {
            _defaultProgramBand.text = value;
          }
        })
        .catchError((_) {
          /* fall back to a blank band field */
        });
    repos.settings
        .get(kDefaultDanceFormKey)
        .then((stored) {
          if (!mounted || _defaultDanceFormUserSet) return;
          setState(() => _defaultDanceForm = danceFormFromStored(stored));
        })
        .catchError((_) {
          if (!mounted || _defaultDanceFormUserSet) return;
          setState(() => _defaultDanceForm = DanceForm.contra);
        });
    repos.settings
        .get(kDefaultDanceFormationShapeKey)
        .then((stored) {
          if (!mounted || _defaultDanceFormationShapeUserSet) return;
          setState(
            () =>
                _defaultDanceFormationShape = formationShapeFromStored(stored),
          );
        })
        .catchError((_) {
          if (!mounted || _defaultDanceFormationShapeUserSet) return;
          setState(
            () => _defaultDanceFormationShape = FormationShape.dupleImproper,
          );
        });
    repos.settings
        .get(kDefaultDanceProgressionKey)
        .then((stored) {
          if (!mounted || _defaultDanceProgressionUserSet) return;
          setState(
            () => _defaultDanceProgression = progressionFromStored(stored),
          );
        })
        .catchError((_) {
          if (!mounted || _defaultDanceProgressionUserSet) return;
          setState(() => _defaultDanceProgression = Progression.single);
        });
    repos.settings
        .get(kDefaultDancePhraseStructureKey)
        .then((stored) {
          if (!mounted || _defaultDancePhraseUserSet) return;
          final raw = dancePhraseStructureRawFromStored(stored);
          if (raw.isNotEmpty) {
            _defaultDancePhrase.text = raw;
          }
        })
        .catchError((_) {
          /* fall back to a blank (standard) phrase field */
        });
    repos.settings
        .get(kDefaultDanceFiguresTemplateKey)
        .then((stored) {
          if (!mounted || _defaultDanceFiguresUserSet) return;
          setState(() {
            _defaultDanceFigureDrafts
              ..clear()
              ..addAll(
                danceFiguresTemplateFromStored(
                  stored,
                ).map(FigureDraft.fromFigure),
              );
          });
        })
        .catchError((_) {
          /* keep the pre-seeded default `stand_still × 8` template */
        });
    repos.settings
        .get(kDefaultMoveParamOverridesKey)
        .then((stored) {
          if (!mounted || _defaultMoveParamOverridesUserSet) return;
          setState(() {
            _defaultMoveParamOverrides = moveParamOverridesFromStored(stored);
            // Merge (don't clear): a move the user added before this read
            // resolves isn't persisted yet, so clearing would make it vanish.
            for (final moveId in _defaultMoveParamOverrides.keys) {
              if (!_moveDefaultsShown.contains(moveId)) {
                _moveDefaultsShown.add(moveId);
              }
            }
          });
        })
        .catchError((_) {
          /* keep the empty override map (pure taxonomy defaults) */
        });
    repos.settings
        .get(kFreeTextEntryKey)
        .then((stored) {
          if (!mounted || _freeTextEntryUserSet) return;
          setState(() => _freeTextEntry = stored is bool ? stored : false);
        })
        .catchError((_) {
          if (!mounted || _freeTextEntryUserSet) return;
          setState(() => _freeTextEntry = false);
        });
  }

  Future<void> _onDefaultProgramCallerChanged(String value) async {
    _defaultCallerUserSet = true;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDefaultProgramCallerKey, value.trim());
  }

  Future<void> _onDefaultProgramBandChanged(String value) async {
    _defaultBandUserSet = true;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDefaultProgramBandKey, value.trim());
  }

  Future<void> _onDefaultDanceFormChanged(DanceForm value) async {
    setState(() {
      _defaultDanceFormUserSet = true;
      _defaultDanceForm = value;
    });
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDefaultDanceFormKey, value.name);
  }

  Future<void> _onDefaultDanceFormationShapeChanged(
    FormationShape value,
  ) async {
    setState(() {
      _defaultDanceFormationShapeUserSet = true;
      _defaultDanceFormationShape = value;
    });
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDefaultDanceFormationShapeKey, value.name);
  }

  Future<void> _onDefaultDanceProgressionChanged(Progression value) async {
    setState(() {
      _defaultDanceProgressionUserSet = true;
      _defaultDanceProgression = value;
    });
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDefaultDanceProgressionKey, value.name);
  }

  Future<void> _onDefaultDancePhraseChanged(String value) async {
    _defaultDancePhraseUserSet = true;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDefaultDancePhraseStructureKey, value.trim());
  }

  /// Persists the "Free-text entry" toggle (#419). Marks it user-set so a late
  /// storage read can't clobber the flip.
  Future<void> _onFreeTextEntryChanged(bool value) async {
    setState(() {
      _freeTextEntryUserSet = true;
      _freeTextEntry = value;
    });
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kFreeTextEntryKey, value);
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
    await repos.settings.set(
      kDefaultDanceFiguresTemplateKey,
      encodeFigures(figures),
    );
  }

  /// Persists the current per-move param overrides as a JSON string (ROADMAP
  /// DD.3), dropping empty inner maps. Marks the setting user-set so a late
  /// storage read can't clobber the in-progress edit.
  Future<void> _persistMoveParamOverrides() async {
    _defaultMoveParamOverridesUserSet = true;
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(
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

  Future<void> _onDefaultCollectionSortChanged(CollectionSort value) async {
    setState(() {
      _defaultSortUserSet = true;
      _defaultCollectionSort = value;
    });
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDefaultCollectionSortKey, value.name);
  }

  Future<void> _onDefaultDanceDetailRenderingChanged(
    DanceDetailRendering value,
  ) async {
    setState(() {
      _defaultRenderingUserSet = true;
      _defaultDanceDetailRendering = value;
    });
    final repos = RepositoriesScope.of(context);
    await repos.settings.set(kDefaultDanceDetailRenderingKey, value.name);
  }

  @override
  Widget build(BuildContext context) {
    _ensureDefaultsLoaded(context);
    return _DefaultsView(
      programCallerController: _defaultProgramCaller,
      onDefaultProgramCallerChanged: _onDefaultProgramCallerChanged,
      programBandController: _defaultProgramBand,
      onDefaultProgramBandChanged: _onDefaultProgramBandChanged,
      defaultCollectionSort: _defaultCollectionSort ?? CollectionSort.title,
      onDefaultCollectionSortChanged: _onDefaultCollectionSortChanged,
      defaultDanceDetailRendering:
          _defaultDanceDetailRendering ?? DanceDetailRendering.activeDialect,
      onDefaultDanceDetailRenderingChanged:
          _onDefaultDanceDetailRenderingChanged,
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
      onFreeTextEntryChanged: _onFreeTextEntryChanged,
      danceFigureTemplateDrafts: _defaultDanceFigureDrafts,
      onDanceFigureTemplateChanged: () {
        setState(() {});
        _persistDanceFiguresTemplate();
      },
      onDanceFigureTemplateAdd: () {
        setState(() => _defaultDanceFigureDrafts.add(FigureDraft()));
        _persistDanceFiguresTemplate();
      },
      onDanceFigureTemplateAddFreeText: (figures) {
        if (figures.isEmpty) return;
        setState(
          () => _defaultDanceFigureDrafts.addAll(
            figures.map(FigureDraft.fromFigure),
          ),
        );
        _persistDanceFiguresTemplate();
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
      moveParamOverrides: _defaultMoveParamOverrides,
      shownMoveDefaults: _moveDefaultsShown,
      onAddMoveDefault: _onAddMoveDefault,
      onRemoveMoveDefault: _onRemoveMoveDefault,
      onMoveParamOverrideChanged: _onMoveParamOverrideChanged,
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
    required this.defaultDanceDetailRendering,
    required this.onDefaultDanceDetailRenderingChanged,
    required this.defaultDanceForm,
    required this.onDefaultDanceFormChanged,
    required this.defaultDanceFormationShape,
    required this.onDefaultDanceFormationShapeChanged,
    required this.defaultDanceProgression,
    required this.onDefaultDanceProgressionChanged,
    required this.dancePhraseController,
    required this.onDefaultDancePhraseChanged,
    required this.freeTextEntry,
    required this.onFreeTextEntryChanged,
    required this.danceFigureTemplateDrafts,
    required this.onDanceFigureTemplateChanged,
    required this.onDanceFigureTemplateAdd,
    required this.onDanceFigureTemplateAddFreeText,
    required this.onDanceFigureTemplateDelete,
    required this.onDanceFigureTemplateDuplicate,
    required this.onDanceFigureTemplateReorder,
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
  final CollectionSort defaultCollectionSort;
  final ValueChanged<CollectionSort> onDefaultCollectionSortChanged;
  final DanceDetailRendering defaultDanceDetailRendering;
  final ValueChanged<DanceDetailRendering> onDefaultDanceDetailRenderingChanged;
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
  final ValueChanged<bool> onFreeTextEntryChanged;

  /// The live draft list backing the starting-figures template editor (ROADMAP
  /// DD.2), plus callbacks mirroring the dance editor's [FigureListEditor]
  /// wiring. Owned by [_DefaultsSectionState]; mutated in the callbacks.
  final List<FigureDraft> danceFigureTemplateDrafts;
  final VoidCallback onDanceFigureTemplateChanged;
  final VoidCallback onDanceFigureTemplateAdd;

  /// Inserts the figure(s) parsed from one free-text line into the template
  /// (#419); only used when [freeTextEntry] is on.
  final ValueChanged<List<Figure>> onDanceFigureTemplateAddFreeText;
  final ValueChanged<FigureDraft> onDanceFigureTemplateDelete;
  final ValueChanged<FigureDraft> onDanceFigureTemplateDuplicate;
  final void Function(int oldIndex, int newIndex) onDanceFigureTemplateReorder;

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
  static const List<CollectionSort> _sortOptions = [
    CollectionSort.title,
    CollectionSort.author,
    CollectionSort.recentlyAdded,
    CollectionSort.lastCalled,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      keyboardDismissBehavior: kTextEntryKeyboardDismiss,
      children: [
        SectionHeader(title: l10n.settingsDefaultsProgramHeader),
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
        SectionHeader(title: l10n.settingsDefaultsDisplayHeader),
        ListTile(
          title: Text(l10n.settingsDefaultsSortTitle),
          subtitle: Text(l10n.settingsDefaultsSortSubtitle),
          trailing: DropdownButton<CollectionSort>(
            key: const ValueKey('defaults-collection-sort'),
            value: defaultCollectionSort,
            onChanged: (value) {
              if (value != null) onDefaultCollectionSortChanged(value);
            },
            items: [
              for (final sort in _sortOptions)
                DropdownMenuItem(
                  value: sort,
                  child: Text(collectionSortLabel(l10n, sort)),
                ),
            ],
          ),
        ),
        SwitchListTile(
          key: const ValueKey('defaults-dance-detail-canonical'),
          value: defaultDanceDetailRendering == DanceDetailRendering.canonical,
          onChanged: (value) => onDefaultDanceDetailRenderingChanged(
            value
                ? DanceDetailRendering.canonical
                : DanceDetailRendering.activeDialect,
          ),
          title: Text(l10n.settingsDefaultsCanonicalTitle),
          subtitle: Text(l10n.settingsDefaultsCanonicalSubtitle),
          isThreeLine: true,
        ),
        SectionHeader(title: l10n.settingsDefaultsAuthoringHeader),
        SwitchListTile(
          key: const ValueKey('defaults-free-text-entry'),
          value: freeTextEntry,
          onChanged: onFreeTextEntryChanged,
          title: Text(l10n.settingsDefaultsFreeTextEntryTitle),
          subtitle: Text(l10n.settingsDefaultsFreeTextEntrySubtitle),
        ),
        Builder(
          builder: (context) {
            final controller = ShorthandMappingsScope.maybeOf(context);
            if (controller == null) return const SizedBox.shrink();
            final count = controller.mappings.length;
            return ListTile(
              key: const ValueKey('defaults-figure-shorthands'),
              enabled: freeTextEntry,
              title: Text(l10n.settingsDefaultsFigureShorthandsTitle),
              subtitle: Text(
                count == 0
                    ? l10n.settingsDefaultsFigureShorthandsEmptySubtitle
                    : l10n.settingsDefaultsFigureShorthandsCountSubtitle(count),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: freeTextEntry
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ShorthandMappingsScreen(),
                      ),
                    )
                  : null,
            );
          },
        ),
        ListTile(
          title: Text(l10n.settingsDefaultsFormTitle),
          subtitle: Text(l10n.settingsDefaultsFormSubtitle),
          trailing: DropdownButton<DanceForm>(
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
        ListTile(
          title: Text(l10n.settingsDefaultsFormationTitle),
          subtitle: Text(l10n.settingsDefaultsFormationSubtitle),
          trailing: DropdownButton<FormationShape>(
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
        ListTile(
          title: Text(l10n.settingsDefaultsProgressionTitle),
          subtitle: Text(l10n.settingsDefaultsProgressionSubtitle),
          trailing: DropdownButton<Progression>(
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
            shorthandMappings: ShorthandMappingsScope.maybeOf(context)?.store,
            onChanged: onDanceFigureTemplateChanged,
            onAdd: onDanceFigureTemplateAdd,
            onAddFreeText: onDanceFigureTemplateAddFreeText,
            onDelete: onDanceFigureTemplateDelete,
            onDuplicate: onDanceFigureTemplateDuplicate,
            onReorder: onDanceFigureTemplateReorder,
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
      ],
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
