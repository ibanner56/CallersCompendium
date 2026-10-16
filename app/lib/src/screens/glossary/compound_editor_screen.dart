import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/active_dialect_scope.dart';
import '../../data/dialect_library_scope.dart';
import '../../data/repositories_scope.dart';
import '../../data/show_custom_figures_scope.dart';
import '../../data/shorthand_mappings_scope.dart';
import '../../editor/figure_draft.dart';
import '../../search/facet_labels.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/figure_list_editor.dart';
import '../../widgets/user_figure_argument_editor.dart';
import 'custom_figure_detail.dart' show compoundParamKindLabel;

final FigureRenderer _renderer = FigureRenderer(contraTaxonomy);

final RegExp _lineBreaks = RegExp('\r\n|[\r\n\u2028\u2029]');

/// The parameter kinds a custom figure may declare: every kind a figure's
/// slot can have, except beats, which are the parts' own (#709).
const List<ParamKind> compoundParamKinds = [
  ParamKind.dancerSet,
  ParamKind.dancerPair,
  ParamKind.handedness,
  ParamKind.shoulder,
  ParamKind.spinDirection,
  ParamKind.direction,
  ParamKind.fraction,
  ParamKind.rotation,
  ParamKind.places,
  ParamKind.flag,
  ParamKind.choice,
  ParamKind.text,
];

/// Creates or edits one of the user's own glossary entries and saves it,
/// popping the saved entry (or null when left): a combination of built-in
/// figures (#709, a compound), a new figure with its own wording, or a term,
/// an entry with no figure (#1023). A new entry chooses which after its
/// parameters (the issue's own suggestion); an existing one keeps its kind,
/// since a figure's uses refer to it as a figure, except that a term can be
/// given a figure ([convertToFigure]).
///
/// A combination:
/// The figures are authored with the same [FigureListEditor] as a dance's,
/// limited to plain taxonomy figures: no custom figure, no meanwhile or
/// modifier. Each figure's slots can then be filled from a declared
/// parameter, or its opposite, where the kinds match and some value fits
/// every slot the parameter fills; any other choice is shown, disabled, with
/// the reason.
///
/// Text is stored canonically and shown here in the active dialect: the entry's
/// own fields with [canonicalizeGlossaryText], and a note on one of its parts
/// with [canonicalizeText], as a dance's figure notes are (see
/// `docs/design/dialect.md`, "User-glossary text").
class CompoundEditorScreen extends StatefulWidget {
  const CompoundEditorScreen({
    super.key,
    this.initial,
    this.termsOnly = false,
    this.convertToFigure = false,
  });

  /// The entry being edited, or null for a new one.
  final UserGlossaryEntry? initial;

  /// A new entry can only be a term: Custom Figures is off, and a term needs
  /// only the Glossary (#1023, maintainer decision 9).
  final bool termsOnly;

  /// Gives the term [initial] a figure: it is saved as a new figure under
  /// the same id and creation time, with its glossary fields as they are
  /// (#1023, maintainer decision 7). There is no way back: a figure's uses
  /// would be left referring to a term.
  final bool convertToFigure;

  @override
  State<CompoundEditorScreen> createState() => _CompoundEditorScreenState();
}

/// One declared parameter while it is edited. Bindings hold the row itself,
/// so renaming it renames every binding.
class _ParamRow {
  _ParamRow(String key, this.kind)
    : controller = TextEditingController(text: key);

  final TextEditingController controller;
  ParamKind kind;

  /// A new figure's: a choice's options, its default, and a flag's wording.
  final List<_ChoiceRow> choices = [];
  Object? defaultValue;
  final TextEditingController label = TextEditingController();

  /// Bumped when the default changes from outside its own field (a kind
  /// changed, a default cleared, its choice removed), so the field is rebuilt
  /// then, and only then: never while the user is choosing or typing in it.
  int defaultEpoch = 0;

  String get key => controller.text.trim();

  void dispose() {
    controller.dispose();
    label.dispose();
    for (final choice in choices) {
      choice.controller.dispose();
    }
  }
}

/// One option of a new figure's choice parameter: its stable id, kept as its
/// label is edited, so the dances using it keep their choice.
class _ChoiceRow {
  _ChoiceRow(this.id, String label)
    : controller = TextEditingController(text: label);

  final String id;
  final TextEditingController controller;
}

/// A slot filled from [param], directly or through its opposite.
class _Binding {
  const _Binding(this.param, this.source);

  final _ParamRow param;
  final CompoundBindingSource source;

  @override
  bool operator ==(Object other) =>
      other is _Binding &&
      identical(other.param, param) &&
      other.source == source;

  @override
  int get hashCode => Object.hash(identityHashCode(param), source);
}

class _CompoundEditorScreenState extends State<CompoundEditorScreen> {
  final _name = TextEditingController();
  final _definition = TextEditingController();
  final _description = TextEditingController();
  final _keywords = TextEditingController();
  final _notes = TextEditingController();
  final List<_ParamRow> _params = [];
  final List<FigureDraft> _drafts = [];

  /// Each figure's bound slots, keyed by the draft itself so a reorder keeps
  /// them with their figure.
  final Map<FigureDraft, Map<String, _Binding>> _bindings = {};

  /// Which kind of entry this is; chosen for a new one, fixed for one stored
  /// (but see [CompoundEditorScreen.convertToFigure]).
  late UserGlossaryEntryKind _kind = widget.convertToFigure
      ? UserGlossaryEntryKind.customFigure
      : switch (widget.initial?.kind) {
          UserGlossaryEntryKind.customFigure =>
            UserGlossaryEntryKind.customFigure,
          UserGlossaryEntryKind.term => UserGlossaryEntryKind.term,
          null when widget.termsOnly => UserGlossaryEntryKind.term,
          _ => UserGlossaryEntryKind.compound,
        };

  /// The dance form the entry is offered in (#1023, maintainer decision 8).
  String _form = defaultGlossaryEntryForm;

  /// A new figure's wording template, shown in the active dialect, and its
  /// default beats.
  final _template = TextEditingController();
  final _beats = TextEditingController(text: '8');

  bool _dirty = false;
  bool _saving = false;
  bool _showRequired = false;
  List<String> _errors = const [];
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    final initial = widget.initial;
    if (initial == null) return;
    final dialect = ActiveDialectScope.of(context);
    String shown(String text) => _renderer.renderFreeText(text, dialect);
    _name.text = shown(initial.name);
    _definition.text = shown(initial.definition);
    _description.text = shown(initial.description);
    _keywords.text = [for (final k in initial.keywords) shown(k)].join(', ');
    _notes.text = initial.notes == null ? '' : shown(initial.notes!);
    _form = glossaryEntryForm(initial.payload);
    // A term has no figure to load, nor does one being given its first.
    if (initial.kind == UserGlossaryEntryKind.term) return;
    if (_kind == UserGlossaryEntryKind.customFigure) {
      _seedFigure(initial.payload, shown);
    } else {
      _seedDefinition(initial.payload, shown);
    }
  }

  /// Loads a stored new figure leniently, as [_seedDefinition] does a
  /// compound, so a broken one can be repaired. Its words are shown in the
  /// active dialect through [shown]; the template's slots are kept as
  /// written.
  void _seedFigure(Object? payload, String Function(String) shown) {
    if (payload is! Map) return;
    if (payload['template'] case final String template) {
      _template.text = mapUserFigureTemplateText(template, shown);
    }
    if (payload['defaultBeats'] case final int beats) _beats.text = '$beats';
    final seen = <String>{};
    for (final raw
        in payload['params'] is List
            ? payload['params'] as List
            : const <Object?>[]) {
      if (raw case {'key': final String key, 'kind': final String kindName}) {
        final kind = compoundParamKinds
            .where((k) => k.name == kindName)
            .firstOrNull;
        if (kind == null || !seen.add(key)) continue;
        final row = _ParamRow(key, kind);
        if (raw['choices'] case final List<Object?> choices) {
          for (final choice in choices) {
            if (choice case {
              'id': final String id,
              'label': final String label,
            }) {
              row.choices.add(_ChoiceRow(id, shown(label)));
            }
          }
        }
        final defaultValue = raw['default'];
        row.defaultValue = defaultValue is String && kind == ParamKind.text
            ? shown(defaultValue)
            : defaultValue;
        if (raw['label'] case final String label) row.label.text = shown(label);
        _params.add(row);
      }
    }
  }

  /// Loads a stored definition leniently, so a broken one can be repaired:
  /// every parameter, figure and binding that still reads is kept, and the
  /// rest is left for the user to put back.
  ///
  /// A figure's note is stored canonical, as a dance's are, and is shown in
  /// the active dialect through [shown].
  void _seedDefinition(Object? payload, String Function(String) shown) {
    if (payload is! Map) return;
    final byKey = <String, _ParamRow>{};
    for (final raw
        in payload['params'] is List
            ? payload['params'] as List
            : const <Object?>[]) {
      if (raw case {'key': final String key, 'kind': final String kindName}) {
        final kind = compoundParamKinds
            .where((k) => k.name == kindName)
            .firstOrNull;
        if (kind == null || byKey.containsKey(key)) continue;
        final row = _ParamRow(key, kind);
        byKey[key] = row;
        _params.add(row);
      }
    }
    final draftsByIndex = <int, FigureDraft>{};
    final rawFigures = payload['figures'] is List
        ? payload['figures'] as List
        : const <Object?>[];
    for (var i = 0; i < rawFigures.length; i++) {
      final raw = rawFigures[i];
      if (raw is! Map) continue;
      try {
        final figure = contraTaxonomy.normalizeFigureV35(
          figureFromJson(raw.cast<String, Object?>()),
        );
        if (figure.move == customMove ||
            figure.move == meanwhileMove ||
            figure.move == modifierMove) {
          continue;
        }
        final draft = FigureDraft.fromFigure(figure);
        draft.note = shown(draft.note);
        draftsByIndex[i] = draft;
        _drafts.add(draft);
      } on Object {
        // diagnostics: silent — a figure that no longer reads is left out; the
        // entry stays broken, and is shown as needing repair, until the user
        // saves a repaired one.
        continue;
      }
    }
    for (final raw
        in payload['bindings'] is List
            ? payload['bindings'] as List
            : const <Object?>[]) {
      if (raw case {
        'figure': final int index,
        'slot': final String slot,
        'param': final String key,
        'source': final String sourceName,
      }) {
        final draft = draftsByIndex[index];
        final param = byKey[key];
        final source = CompoundBindingSource.values
            .where((s) => s.name == sourceName)
            .firstOrNull;
        if (draft == null || param == null || source == null) continue;
        (_bindings[draft] ??= {})[slot] = _Binding(param, source);
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _definition,
      _description,
      _keywords,
      _notes,
      _template,
      _beats,
    ]) {
      c.dispose();
    }
    for (final p in _params) {
      p.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {
    _dirty = true;
    _errors = const [];
  });

  // ---------------------------------------------------------------- model --

  /// The slots of [draft]'s move a parameter may fill, in the move's order:
  /// every slot but beats, and none an alias pins without an inverse pair.
  List<MapEntry<String, ParamSpec>> _slotsOf(FigureDraft draft) {
    final move = draft.move;
    if (move == null || draft.isContainerDraft || move == customMove) {
      return const [];
    }
    final def = contraTaxonomy.resolve(move);
    if (def == null) return const [];
    final alias = contraTaxonomy.aliases[move];
    return [
      for (final slot in def.params.entries)
        if (slot.key != 'beats' &&
            !(alias != null &&
                alias.inversePairId == null &&
                alias.pinnedParams.containsKey(slot.key)))
          slot,
    ];
  }

  /// The definition as it stands, with [override] in place of the binding of
  /// [draft]'s [slot] when given (null [override] unbinds it).
  ///
  /// [canonicalizeNote] stores each figure's note as a dance's figure notes
  /// are stored, which the save passes, since an expansion copies the note
  /// into a dance.
  CompoundDefinition _definitionNow({
    FigureDraft? draft,
    String? slot,
    _Binding? override,
    String Function(String)? canonicalizeNote,
  }) {
    final figures = <Figure>[];
    final indexOf = <FigureDraft, int>{};
    for (final d in _drafts) {
      final figure = canonicalizeNote == null
          ? d.toFigure()
          : d.toFigure(canonicalizeNote: canonicalizeNote);
      if (figure == null) continue;
      indexOf[d] = figures.length;
      figures.add(figure);
    }
    final bindings = <CompoundSlotBinding>[];
    for (final MapEntry(key: d, value: slots) in _bindings.entries) {
      final index = indexOf[d];
      if (index == null) continue;
      final valid = {for (final s in _slotsOf(d)) s.key};
      final effective = {...slots};
      if (identical(d, draft) && slot != null) {
        if (override == null) {
          effective.remove(slot);
        } else {
          effective[slot] = override;
        }
      }
      for (final MapEntry(key: slotKey, value: binding) in effective.entries) {
        if (!valid.contains(slotKey) || !_params.contains(binding.param)) {
          continue;
        }
        bindings.add(
          CompoundSlotBinding(
            figureIndex: index,
            slotKey: slotKey,
            paramKey: binding.param.key,
            source: binding.source,
          ),
        );
      }
    }
    if (draft != null && slot != null && override != null) {
      final index = indexOf[draft];
      final present = bindings.any(
        (b) => b.figureIndex == index && b.slotKey == slot,
      );
      if (index != null && !present) {
        bindings.add(
          CompoundSlotBinding(
            figureIndex: index,
            slotKey: slot,
            paramKey: override.param.key,
            source: override.source,
          ),
        );
      }
    }
    return CompoundDefinition(
      params: [
        for (final p in _params) CompoundParam(key: p.key, kind: p.kind),
      ],
      figures: figures,
      bindings: bindings,
      form: _form,
      extra: compoundPayloadExtra(widget.initial?.payload),
    );
  }

  /// The new figure as it stands, its words passed through [store] (the save
  /// canonicalizes them; the preview passes the same).
  UserFigureDefinition _figureNow(String Function(String) store) {
    final initialPayload = widget.initial?.payload;
    // A term given a figure keeps every key it stored but its form; none of
    // them names the built-in figure it was copied from.
    final copiedFrom =
        initialPayload is Map &&
            widget.initial?.kind == UserGlossaryEntryKind.customFigure
        ? initialPayload['copiedFrom']
        : null;
    return UserFigureDefinition(
      form: _form,
      // One line: a break reads as a space, not as nothing.
      template: mapUserFigureTemplateText(
        _template.text.replaceAll(_lineBreaks, ' ').trim(),
        store,
      ),
      defaultBeats: int.tryParse(_beats.text.trim()) ?? -1,
      params: [for (final p in _params) _figureParam(p, store)],
      copiedFrom: copiedFrom is String ? copiedFrom : null,
      extra: userFigurePayloadExtra(initialPayload),
    );
  }

  UserFigureParam _figureParam(_ParamRow row, String Function(String) store) {
    final choices = row.kind == ParamKind.choice
        ? [
            for (final c in row.choices)
              UserFigureChoice(
                id: c.id,
                label: store(c.controller.text.trim()),
              ),
          ]
        : const <UserFigureChoice>[];
    final label = row.label.text.trim();
    var defaultValue = row.defaultValue;
    if (defaultValue is String && row.kind == ParamKind.text) {
      defaultValue = defaultValue.trim().isEmpty
          ? null
          : store(defaultValue.trim());
    }
    final withoutDefault = UserFigureParam(
      key: row.key,
      kind: row.kind,
      choices: choices,
      label: row.kind == ParamKind.flag && label.isNotEmpty
          ? store(label)
          : null,
    );
    // A default the parameter's kind or choices no longer take is dropped,
    // not saved broken: a kind changed after the default was chosen.
    if (defaultValue == null || !withoutDefault.spec.validate(defaultValue)) {
      return withoutDefault;
    }
    return UserFigureParam(
      key: withoutDefault.key,
      kind: withoutDefault.kind,
      choices: withoutDefault.choices,
      defaultValue: defaultValue,
      label: withoutDefault.label,
    );
  }

  /// How the new figure reads with its defaults, or null while it can't be
  /// rendered.
  String? _preview(Dialect dialect) {
    String stored(String text) => canonicalizeGlossaryText(text, dialect);
    final figure = _figureNow(stored);
    if (validateUserFigure(
      figure,
    ).any((i) => i.severity == ValidationSeverity.error)) {
      return null;
    }
    const previewId = 'preview';
    final catalog = UserFigureCatalog.fromEntries([
      UserGlossaryEntry(
        id: previewId,
        kindName: UserGlossaryEntryKind.customFigure.name,
        name: stored(_name.text.trim()),
        definition: '',
        description: '',
        payload: figure.toJson(),
        createdAt: DateTime.utc(2000),
      ),
    ]);
    final renderer = FigureRenderer(contraTaxonomy, userFigures: catalog);
    final use = userFigureUseFigure(
      id: previewId,
      args: {
        for (final p in figure.params)
          if (p.defaultValue != null) p.key: p.defaultValue,
      },
      text: '',
    );
    if (renderer.renderUserFigureCanonical(use) == null) return null;
    return renderer.render(use, dialect);
  }

  /// Why [candidate] cannot fill [draft]'s [slot], or null when it can.
  String? _unavailableReason(
    AppLocalizations l10n,
    FigureDraft draft,
    String slot,
    ParamSpec spec,
    _Binding candidate,
  ) {
    final param = candidate.param;
    if (param.key.isEmpty) return l10n.compoundBindingNoName;
    if (param.kind != spec.kind) {
      return l10n.compoundBindingWrongKind(
        compoundParamKindLabel(l10n, param.kind),
        compoundParamKindLabel(l10n, spec.kind),
      );
    }
    if (candidate.source == CompoundBindingSource.opposite &&
        ParamOpposites.coverage(param.kind) == OppositeCoverage.none) {
      return l10n.compoundBindingNoOpposite;
    }
    final allowed = allowedValues(
      _definitionNow(draft: draft, slot: slot, override: candidate),
      param.key,
      contraTaxonomy,
    );
    if (allowed != null && allowed.isEmpty) {
      return l10n.compoundBindingNoSharedValues;
    }
    return null;
  }

  // ---------------------------------------------------------------- save --

  Future<void> _save() async {
    // Claimed before the first await, so a second tap cannot pass the checks
    // while the first is still running and save a second entry.
    if (_saving) return;
    setState(() => _saving = true);
    var saved = false;
    try {
      saved = await _trySave();
    } finally {
      if (!saved && mounted) setState(() => _saving = false);
    }
  }

  /// Validates, asks about unused parameters, and stores the entry; true once
  /// it is stored and the editor closed.
  Future<bool> _trySave() async {
    final l10n = AppLocalizations.of(context);
    final dialect = ActiveDialectScope.of(context);
    final repos = RepositoriesScope.of(context);
    final navigator = Navigator.of(context);

    final errors = <String>[];
    final name = _name.text.trim();
    final requiredMissing =
        name.isEmpty ||
        _definition.text.trim().isEmpty ||
        _description.text.trim().isEmpty;
    if (requiredMissing) errors.add(l10n.compoundEditorRequired);

    final keys = [for (final p in _params) p.key];
    if (_kind == UserGlossaryEntryKind.compound &&
        (keys.any((k) => k.isEmpty) || keys.toSet().length != keys.length)) {
      errors.add(l10n.compoundEditorParamNames);
    }

    if (name.isNotEmpty) {
      // Compared as stored, canonical: two names typed differently can store
      // alike ("Larks swing", "Gents swing" under Larks/Robins), and the
      // Glossary flags a duplicate by its stored name.
      final others = (await repos.userGlossary.listAll())
          .where((e) => e.id != widget.initial?.id)
          .toList();
      if (!mounted) return false;
      Set<GlossaryNameSource> collisionsWith(
        Iterable<UserGlossaryEntry> entries,
      ) => glossaryNameCollisions(
        canonicalizeGlossaryText(name, dialect),
        taxonomy: contraTaxonomy,
        dialects: [
          dialect,
          ...?DialectLibraryScope.maybeOf(context)?.customDialects,
        ],
        shorthandTokens: ShorthandMappingsScope.tokensOf(context),
        userEntryNames: entries.map((e) => e.name),
      );
      if (collisionsWith(others).isNotEmpty) {
        // While Custom Figures is off the Glossary lists only terms, so a
        // clash with one of the user's figures says where that figure is.
        final shown = customFiguresShown(context)
            ? others
            : others.where((e) => e.kind == UserGlossaryEntryKind.term);
        errors.add(
          collisionsWith(shown).isEmpty
              ? l10n.compoundEditorNameTakenHidden(name)
              : l10n.compoundEditorNameTaken(name),
        );
      }
    }

    final Map<String, Object?> payload;
    final List<String> unused;
    if (_kind == UserGlossaryEntryKind.term) {
      payload = glossaryTermPayload(_form, previous: widget.initial?.payload);
      unused = const [];
    } else if (_kind == UserGlossaryEntryKind.customFigure) {
      final figure = _figureNow(
        (text) => canonicalizeGlossaryText(text, dialect),
      );
      final issues = validateUserFigure(figure);
      for (final issue in issues) {
        if (issue.severity != ValidationSeverity.error) continue;
        final message = switch (issue.code) {
          UserFigureIssueCodes.badTemplate => l10n.userFigureEditorBadWording,
          UserFigureIssueCodes.unknownSlot => l10n.userFigureEditorUnknownSlot(
            '{${issue.data['slot']}}',
          ),
          UserFigureIssueCodes.badParamKey ||
          UserFigureIssueCodes.badParamKind => l10n.userFigureEditorParamNames,
          UserFigureIssueCodes.badChoices => l10n.userFigureEditorBadChoices(
            '${issue.data['param']}',
          ),
          UserFigureIssueCodes.badBeats => l10n.userFigureEditorBadBeats,
          UserFigureIssueCodes.tooLarge => l10n.compoundEditorTooLarge,
          UserFigureIssueCodes.tooLong => l10n.compoundEditorTooLong,
          // A label over its bound; an empty one is not saved at all.
          _ => l10n.compoundEditorTooLong,
        };
        if (!errors.contains(message)) errors.add(message);
      }
      unused = [
        for (final issue in issues)
          if (issue.code == UserFigureIssueCodes.unusedParam)
            '${issue.data['param']}',
      ];
      payload = figure.toJson();
    } else {
      final definition = _definitionNow(
        canonicalizeNote: (note) => canonicalizeText(note.trim(), dialect),
      );
      final issues = validateCompound(definition, contraTaxonomy);
      for (final issue in issues) {
        if (issue.severity != ValidationSeverity.error) continue;
        final message = switch (issue.code) {
          CompoundIssueCodes.empty => l10n.compoundEditorNoFigures,
          CompoundIssueCodes.badParamKey => null, // reported above
          CompoundIssueCodes.emptyDomain => l10n.compoundEditorEmptyDomain(
            '${issue.data['param']}',
          ),
          CompoundIssueCodes.tooLarge => l10n.compoundEditorTooLarge,
          // A binding that a later edit (a figure's move, a parameter's kind)
          // made unusable; the dropdown shows it disabled, with why.
          CompoundIssueCodes.typeMismatch ||
          CompoundIssueCodes.noOpposite ||
          CompoundIssueCodes.danglingBinding ||
          CompoundIssueCodes.doubleBinding ||
          CompoundIssueCodes.beatsBinding ||
          CompoundIssueCodes.pinnedSlot => l10n.compoundEditorBindingInvalid,
          _ => l10n.compoundEditorInvalidFigures,
        };
        if (message != null && !errors.contains(message)) errors.add(message);
      }

      unused = [
        for (final issue in issues)
          if (issue.code == CompoundIssueCodes.unusedParam)
            '${issue.data['param']}',
      ];
      payload = definition.toJson();
    }

    if (errors.isNotEmpty) {
      setState(() {
        _errors = errors;
        _showRequired = requiredMissing;
      });
      return false;
    }

    if (unused.isNotEmpty) {
      final saveAnyway = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.compoundEditorUnusedTitle),
          content: Text(
            _kind == UserGlossaryEntryKind.customFigure
                ? l10n.userFigureEditorUnusedBody(unused.join(', '))
                : l10n.compoundEditorUnusedBody(unused.join(', ')),
          ),
          actions: [
            TextButton(
              key: const ValueKey('compound-unused-back'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.compoundEditorUnusedBack),
            ),
            FilledButton(
              key: const ValueKey('compound-unused-save'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.compoundEditorUnusedSave),
            ),
          ],
        ),
      );
      if (saveAnyway != true || !mounted) return false;
    }

    String stored(String text) =>
        canonicalizeGlossaryText(text.trim(), dialect);
    final notes = _notes.text.trim();
    final entry = UserGlossaryEntry(
      id: widget.initial?.id ?? uuidV4(),
      kindName: _kind.name,
      name: stored(name),
      definition: stored(_definition.text),
      description: stored(_description.text),
      keywords: [
        for (final k in _keywords.text.split(','))
          if (k.trim().isNotEmpty) stored(k),
      ],
      notes: notes.isEmpty ? null : stored(notes),
      payload: payload,
      createdAt: widget.initial?.createdAt ?? DateTime.now().toUtc(),
    );
    try {
      await repos.userGlossary.upsert(entry);
    } on UserGlossaryEntryInvalid {
      // diagnostics: silent — shown inline; a field over its bound is the user's to shorten.
      if (mounted) setState(() => _errors = [l10n.compoundEditorTooLong]);
      return false;
    }
    _dirty = false;
    navigator.pop(entry);
    return true;
  }

  Future<bool> _confirmDiscard() async {
    final l10n = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.danceEditorDiscardChangesTitle),
        content: Text(l10n.compoundEditorDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('compound-discard'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.danceEditorDiscard),
          ),
        ],
      ),
    );
    return discard == true;
  }

  // ---------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dialect = ActiveDialectScope.of(context);

    Widget heading(String title, String help) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(help, style: theme.textTheme.bodySmall),
        ],
      ),
    );

    Widget field(
      String key,
      TextEditingController controller,
      String label, {
      String? helper,
      bool required = false,
      int maxLength = maxUserGlossaryTextLength,
      int? maxLines = 1,
    }) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: TextField(
        key: ValueKey(key),
        controller: controller,
        maxLength: maxLength,
        minLines: 1,
        maxLines: maxLines,
        onChanged: (_) => _changed(),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          errorText: required && _showRequired && controller.text.trim().isEmpty
              ? l10n.compoundEditorFieldRequired
              : null,
          border: const OutlineInputBorder(),
        ),
      ),
    );

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!await _confirmDiscard()) return;
        if (!context.mounted) return;
        _dirty = false;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.convertToFigure
                ? l10n.glossaryTermMakeFigureTitle
                : widget.initial == null
                ? (_kind == UserGlossaryEntryKind.term
                      ? l10n.glossaryTermTitleNew
                      : l10n.compoundEditorTitleNew)
                : l10n.compoundEditorTitleEdit,
          ),
          actions: [
            TextButton(
              key: const ValueKey('compound-editor-save'),
              onPressed: _saving ? null : _save,
              child: Text(l10n.commonSave),
            ),
          ],
        ),
        body: ListView(
          key: const ValueKey('compound-editor'),
          children: [
            if (_errors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  0,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    key: const ValueKey('compound-editor-errors'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in _errors)
                        Text(
                          e,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                    ],
                  ),
                ),
              ),
            field(
              'compound-name',
              _name,
              l10n.compoundEditorName,
              required: true,
              maxLength: maxUserGlossaryNameLength,
            ),
            field(
              'compound-definition',
              _definition,
              l10n.compoundEditorDefinition,
              helper: l10n.compoundEditorDefinitionHelper,
              required: true,
              maxLines: 3,
            ),
            field(
              'compound-description',
              _description,
              l10n.compoundEditorDescription,
              required: true,
              maxLines: 8,
            ),
            field(
              'compound-keywords',
              _keywords,
              l10n.compoundEditorKeywords,
              helper: l10n.compoundEditorKeywordsHelper,
              maxLength: maxUserGlossaryNameLength * 4,
            ),
            field(
              'compound-notes',
              _notes,
              l10n.compoundEditorNotes,
              helper: l10n.compoundEditorOptional,
              maxLines: 6,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: DropdownButtonFormField<String>(
                key: const ValueKey('glossary-entry-form'),
                initialValue: _form,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.glossaryEntryFormLabel,
                  helperText: l10n.glossaryEntryFormHelper,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final form in DanceForm.values)
                    DropdownMenuItem(
                      value: form.name,
                      child: Text(danceFormLabel(l10n, form)),
                    ),
                  // A form a later build added is kept, as written.
                  if (!DanceForm.values.any((f) => f.name == _form))
                    DropdownMenuItem(value: _form, child: Text(_form)),
                ],
                onChanged: (form) {
                  if (form == null) return;
                  _form = form;
                  _changed();
                },
              ),
            ),
            if (_kind != UserGlossaryEntryKind.term) ...[
              heading(l10n.compoundEditorParams, l10n.compoundEditorParamsHelp),
              for (final (i, row) in _params.indexed) ...[
                Padding(
                  key: ValueKey('compound-param-$i'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.xs,
                    0,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          key: ValueKey('compound-param-$i-name'),
                          controller: row.controller,
                          maxLength: _kind == UserGlossaryEntryKind.customFigure
                              ? maxUserFigureParamKeyLength
                              : maxCompoundParamKeyLength,
                          onChanged: (_) => _changed(),
                          decoration: InputDecoration(
                            labelText: l10n.compoundEditorParamName,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<ParamKind>(
                          key: ValueKey('compound-param-$i-kind'),
                          initialValue: row.kind,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: l10n.compoundEditorParamKind,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            for (final kind in compoundParamKinds)
                              DropdownMenuItem(
                                value: kind,
                                child: Text(compoundParamKindLabel(l10n, kind)),
                              ),
                          ],
                          onChanged: (kind) {
                            if (kind == null) return;
                            if (kind != row.kind) {
                              // A default of the old kind means nothing in the
                              // new one, and could even pass for one of it (a
                              // choice id as text).
                              row.defaultValue = null;
                              row.defaultEpoch++;
                            }
                            row.kind = kind;
                            _changed();
                          },
                        ),
                      ),
                      IconButton(
                        key: ValueKey('compound-param-$i-remove'),
                        tooltip: l10n.compoundEditorRemoveParam,
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () {
                          _params.removeAt(i);
                          for (final slots in _bindings.values) {
                            slots.removeWhere(
                              (_, b) => identical(b.param, row),
                            );
                          }
                          // Disposed after the frame that stops building it.
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => row.dispose(),
                          );
                          _changed();
                        },
                      ),
                    ],
                  ),
                ),
                if (_kind == UserGlossaryEntryKind.customFigure)
                  _figureParamExtras(context, l10n, dialect, i, row),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('compound-add-param'),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.compoundEditorAddParam),
                    onPressed:
                        _params.length >=
                            (_kind == UserGlossaryEntryKind.customFigure
                                ? maxUserFigureParams
                                : maxCompoundParams)
                        ? null
                        : () {
                            _params.add(_ParamRow('', ParamKind.dancerSet));
                            _changed();
                          },
                  ),
                ),
              ),
            ],
            if (widget.initial == null && !widget.termsOnly) ...[
              heading(
                l10n.glossaryEntryKindHeading,
                l10n.glossaryEntryKindHelp,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: SegmentedButton<UserGlossaryEntryKind>(
                  key: const ValueKey('glossary-entry-kind'),
                  segments: [
                    ButtonSegment(
                      value: UserGlossaryEntryKind.compound,
                      label: Text(l10n.glossaryEntryKindCombination),
                    ),
                    ButtonSegment(
                      value: UserGlossaryEntryKind.customFigure,
                      label: Text(l10n.glossaryEntryKindNewFigure),
                    ),
                    ButtonSegment(
                      value: UserGlossaryEntryKind.term,
                      label: Text(l10n.glossaryEntryKindTerm),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (kinds) {
                    _kind = kinds.single;
                    _changed();
                  },
                ),
              ),
            ],
            if (_kind == UserGlossaryEntryKind.customFigure)
              ..._wordingSection(context, l10n, dialect, heading)
            else if (_kind == UserGlossaryEntryKind.compound) ...[
              heading(
                l10n.compoundEditorFigures,
                l10n.compoundEditorFiguresHelp,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: FigureListEditor(
                  drafts: _drafts,
                  taxonomy: contraTaxonomy,
                  phraseStructure: PhraseStructure.standard,
                  dialect: dialect,
                  onChanged: _changed,
                  onAdd: () {
                    if (_drafts.length >= maxCompoundFigures) return;
                    _drafts.add(FigureDraft());
                    _changed();
                  },
                  onDelete: (draft) {
                    _drafts.remove(draft);
                    _bindings.remove(draft);
                    _changed();
                  },
                  onReorder: (oldIndex, newIndex) {
                    final draft = _drafts.removeAt(oldIndex);
                    _drafts.insert(newIndex, draft);
                    _changed();
                  },
                  showPhraseStructure: false,
                  allowDuplicating: false,
                  allowModifierSelection: false,
                  allowNestedContainerSelection: false,
                  allowCustom: false,
                ),
              ),
              if (_params.isNotEmpty) ...[
                heading(
                  l10n.compoundEditorBindings,
                  l10n.compoundEditorBindingsHelp,
                ),
                for (final (i, draft) in _drafts.indexed)
                  if (_slotsOf(draft).isNotEmpty)
                    _bindingCard(context, l10n, dialect, i, draft),
              ],
            ],
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  /// A new figure's parameter beyond its name and kind: a choice's options, a
  /// flag's wording, and its default.
  Widget _figureParamExtras(
    BuildContext context,
    AppLocalizations l10n,
    Dialect dialect,
    int index,
    _ParamRow row,
  ) {
    String stored(String text) => canonicalizeGlossaryText(text, dialect);
    final param = _figureParam(row, stored);
    return Padding(
      key: ValueKey('user-figure-param-$index-extras'),
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.xl,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (row.kind == ParamKind.choice) ...[
            for (final (c, choice) in row.choices.indexed)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: ValueKey('user-figure-param-$index-choice-$c'),
                        controller: choice.controller,
                        maxLength: maxUserFigureLabelLength,
                        onChanged: (_) => _changed(),
                        decoration: InputDecoration(
                          labelText: l10n.userFigureEditorChoiceLabel(c + 1),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      key: ValueKey(
                        'user-figure-param-$index-choice-$c-remove',
                      ),
                      tooltip: l10n.userFigureEditorRemoveChoice,
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () {
                        row.choices.removeAt(c);
                        if (row.defaultValue == choice.id) {
                          row.defaultValue = null;
                          row.defaultEpoch++;
                        }
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => choice.controller.dispose(),
                        );
                        _changed();
                      },
                    ),
                  ],
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: ValueKey('user-figure-param-$index-add-choice'),
                icon: const Icon(Icons.add),
                label: Text(l10n.userFigureEditorAddChoice),
                onPressed: row.choices.length >= maxUserFigureChoices
                    ? null
                    : () {
                        row.choices.add(
                          _ChoiceRow(
                            newUserFigureChoiceId({
                              for (final c in row.choices) c.id,
                            }),
                            '',
                          ),
                        );
                        _changed();
                      },
              ),
            ),
          ],
          if (row.kind == ParamKind.flag)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: TextField(
                key: ValueKey('user-figure-param-$index-label'),
                controller: row.label,
                maxLength: maxUserFigureLabelLength,
                onChanged: (_) => _changed(),
                decoration: InputDecoration(
                  labelText: l10n.userFigureEditorFlagLabel,
                  helperText: l10n.userFigureEditorFlagLabelHelper,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          if (row.key.isNotEmpty &&
              (row.kind != ParamKind.choice || row.choices.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: UserFigureArgumentEditor(
                      key: ValueKey(
                        'user-figure-param-$index-default-${row.defaultEpoch}',
                      ),
                      keyPrefix: 'user-figure-param-$index-default',
                      param: param,
                      value: row.defaultValue,
                      dialect: dialect,
                      label: l10n.userFigureEditorDefault,
                      allowNone: true,
                      onChanged: (value) {
                        row.defaultValue = value;
                        _changed();
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// A new figure's wording, default beats and how it reads.
  List<Widget> _wordingSection(
    BuildContext context,
    AppLocalizations l10n,
    Dialect dialect,
    Widget Function(String title, String help) heading,
  ) {
    final slots = _figureNow((text) => text).slots;
    final preview = _preview(dialect);
    final theme = Theme.of(context);
    return [
      heading(
        l10n.userFigureEditorWording,
        l10n.userFigureEditorWordingHelp('{who}'),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          0,
        ),
        child: TextField(
          key: const ValueKey('user-figure-wording'),
          controller: _template,
          inputFormatters: [
            FilteringTextInputFormatter.deny(
              _lineBreaks,
              replacementString: ' ',
            ),
          ],
          maxLength: kMaxMoveWordingLength,
          minLines: 1,
          maxLines: 3,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(
            labelText: l10n.userFigureEditorWording,
            helperText: l10n.userFigureEditorWordingSlots(
              [for (final slot in slots) '{$slot}'].join(', '),
            ),
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          0,
        ),
        child: TextField(
          key: const ValueKey('user-figure-default-beats'),
          controller: _beats,
          keyboardType: TextInputType.number,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(
            labelText: l10n.userFigureEditorDefaultBeats,
            helperText: l10n.userFigureEditorDefaultBeatsHelper,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          0,
        ),
        child: Text(
          preview == null
              ? l10n.userFigureEditorPreviewUnavailable
              : l10n.userFigureEditorPreview(preview),
          key: const ValueKey('user-figure-preview'),
          style: theme.textTheme.bodyMedium,
        ),
      ),
    ];
  }

  Widget _bindingCard(
    BuildContext context,
    AppLocalizations l10n,
    Dialect dialect,
    int index,
    FigureDraft draft,
  ) {
    final figure = draft.toFigure();
    final slots = _slotsOf(draft);
    final bound = _bindings[draft] ?? const <String, _Binding>{};
    return Card(
      key: ValueKey('compound-bindings-$index'),
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.compoundEditorFigureN(
                index + 1,
                figure == null ? '' : _renderer.render(figure, dialect),
              ),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final MapEntry(key: slot, value: spec) in slots)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: DropdownButtonFormField<_Binding?>(
                  key: ValueKey('compound-binding-$index-$slot'),
                  initialValue: bound[slot],
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: figureParamKeyLabel(
                      l10n,
                      slot,
                      moveId: draft.move,
                    ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem<_Binding?>(
                      value: null,
                      child: Text(l10n.compoundBindingFixed),
                    ),
                    // Every choice is listed, the unavailable ones disabled
                    // with their reason, so a binding made unavailable by a
                    // later edit is still shown as what it is.
                    for (final param in _params)
                      for (final source in CompoundBindingSource.values)
                        _bindingItem(
                          l10n,
                          draft,
                          slot,
                          spec,
                          _Binding(param, source),
                        ),
                  ],
                  onChanged: (binding) {
                    final slotsOfDraft = _bindings[draft] ??= {};
                    if (binding == null) {
                      slotsOfDraft.remove(slot);
                    } else {
                      slotsOfDraft[slot] = binding;
                    }
                    _changed();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  DropdownMenuItem<_Binding?> _bindingItem(
    AppLocalizations l10n,
    FigureDraft draft,
    String slot,
    ParamSpec spec,
    _Binding candidate,
  ) {
    final label = candidate.source == CompoundBindingSource.declared
        ? candidate.param.key
        : l10n.compoundBindingOpposite(candidate.param.key);
    final reason = _unavailableReason(l10n, draft, slot, spec, candidate);
    return DropdownMenuItem<_Binding?>(
      value: candidate,
      enabled: reason == null,
      child: Text(
        reason == null ? label : l10n.compoundBindingUnavailable(label, reason),
      ),
    );
  }
}
