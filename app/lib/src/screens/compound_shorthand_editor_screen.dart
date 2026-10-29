import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';
import '../data/repositories_scope.dart';
import '../data/user_figures_scope.dart';
import '../editor/figure_draft.dart';
import '../editor/user_figure_draft.dart';
import '../glossary/custom_figures.dart';
import '../widgets/compound_argument_editor.dart';
import '../widgets/shorthand_shadow_warning.dart';
import '../widgets/user_figure_use_editor.dart';
import '../widgets/app_bar_text_action.dart';
import '../widgets/confirm_discard_changes.dart';

/// Creates or edits one shorthand for one of the user's own figures: a token
/// that stands for a compound (#709) or a new figure (#1023) with the values
/// chosen here. Pops the edited [CompoundShorthand] or [UserFigureShorthand],
/// whichever kind of figure was chosen, or nothing when cancelled. Backing out
/// with unsaved changes asks first ([DiscardChangesGuard]).
///
/// Only figures this build can use are offered: compounds it can expand, and
/// new figures whose definition decodes. Each argument is chosen within what
/// the figure accepts, as on a dance-editor row; a new figure's beats too.
class CompoundShorthandEditorScreen extends StatefulWidget {
  const CompoundShorthandEditorScreen({
    super.key,
    this.initial,
    this.initialUserFigure,
    this.existingTokens = const {},
  }) : assert(
         initial == null || initialUserFigure == null,
         'one shorthand is edited at a time',
       );

  /// The compound shorthand being edited, or null.
  final CompoundShorthand? initial;

  /// The shorthand for a new figure being edited, or null. Both null for a
  /// new shorthand.
  final UserFigureShorthand? initialUserFigure;

  /// The normalized tokens of every other shorthand, of any kind.
  final Set<String> existingTokens;

  @override
  State<CompoundShorthandEditorScreen> createState() =>
      _CompoundShorthandEditorScreenState();
}

class _CompoundShorthandEditorScreenState
    extends State<CompoundShorthandEditorScreen> {
  static final FigureRenderer _renderer = FigureRenderer(contraTaxonomy);

  late final String _initialToken =
      widget.initial?.token ?? widget.initialUserFigure?.token ?? '';
  late final TextEditingController _token = TextEditingController(
    text: _initialToken,
  );
  StreamSubscription<List<UserGlossaryEntry>>? _sub;
  CompendiumRepositories? _repos;

  /// The compounds that can be expanded, by entry id, in name order.
  Map<String, ({UserGlossaryEntry entry, CompoundDefinition definition})>?
  _compounds;

  /// The new figures that can be used, by entry id, in name order (#1023).
  Map<String, ({UserGlossaryEntry entry, UserFigureDefinition definition})>?
  _figures;

  /// The figure chosen: a compound's id ([_compoundId]), or a new figure's
  /// ([_figureId]); at most one is set.
  late String? _compoundId = widget.initial?.compoundId;
  late String? _figureId = widget.initialUserFigure?.figureId;
  late final Map<String, Object?> _args = {...?widget.initial?.args};

  /// A new figure's use, as a dance-editor row holds it: its arguments and
  /// beats. Seeded when the figures are first read.
  Map<String, Object?>? _useParams;
  String? _error;

  /// The choices as the editor opened, for [_dirty], beside the token's
  /// [_initialToken]. [_initialUseParams] is filled in when the figures are
  /// first read, alongside [_useParams].
  late final String? _initialCompoundId = widget.initial?.compoundId;
  late final String? _initialFigureId = widget.initialUserFigure?.figureId;
  late final Map<String, Object?> _initialArgs = {...?widget.initial?.args};
  Map<String, Object?>? _initialUseParams;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repos = RepositoriesScope.maybeOf(context);
    if (identical(repos, _repos)) return;
    _repos = repos;
    unawaited(_sub?.cancel());
    _sub = repos?.userGlossary.watchAll().listen((entries) {
      if (!mounted) return;
      final usable =
          [
            for (final entry in entries)
              if (entry.kind == UserGlossaryEntryKind.compound)
                if (decodeCompoundDefinition(entry.payload, contraTaxonomy)
                    case final definition?)
                  (entry: entry, definition: definition),
          ]..sort(
            (a, b) => a.entry.name.toLowerCase().compareTo(
              b.entry.name.toLowerCase(),
            ),
          );
      final figures =
          [
            for (final entry in entries)
              if (entry.kind == UserGlossaryEntryKind.customFigure)
                if (decodeUserFigureDefinition(entry.payload)
                    case final definition?)
                  (entry: entry, definition: definition),
          ]..sort(
            (a, b) => a.entry.name.toLowerCase().compareTo(
              b.entry.name.toLowerCase(),
            ),
          );
      setState(() {
        _compounds = {for (final c in usable) c.entry.id: c};
        _figures = {for (final f in figures) f.entry.id: f};
        // The shorthand being edited opens with its own values, once.
        if (_useParams == null && widget.initialUserFigure != null) {
          final initial = widget.initialUserFigure!;
          final figure = _figures![initial.figureId];
          if (figure != null) {
            _useParams = userFigureDraftParams(
              figure.entry,
              figure.definition,
              args: initial.args,
              beats: initial.beats,
            );
            _initialUseParams = _useParams;
          }
        }
      });
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _token.dispose();
    super.dispose();
  }

  /// Whether leaving now would lose a change: the token, the figure chosen,
  /// or its values.
  bool get _dirty =>
      _token.text.trim() != _initialToken.trim() ||
      _compoundId != _initialCompoundId ||
      _figureId != _initialFigureId ||
      !_sameValue(_args, _initialArgs) ||
      !_sameValue(_useParams, _initialUseParams);

  /// Deep equality over the JSON-shaped values a figure's arguments hold.
  static bool _sameValue(Object? a, Object? b) => switch ((a, b)) {
    (final Map<Object?, Object?> a, final Map<Object?, Object?> b) =>
      a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _sameValue(a[k], b[k])),
    (final List<Object?> a, final List<Object?> b) =>
      a.length == b.length &&
          Iterable<int>.generate(a.length).every((i) => _sameValue(a[i], b[i])),
    _ => a == b,
  };

  /// Whether this makes a new shorthand rather than editing one of either
  /// kind.
  bool get _isNew => widget.initial == null && widget.initialUserFigure == null;

  /// A choice's value in the figure list: which kind, and its id.
  static String _compoundValue(String id) => 'compound:$id';
  static String _figureValue(String id) => userFigureKeyFor(id);

  void _pick(String? value) {
    if (value != null && isUserFigureKey(value)) {
      final id = value.substring(userFigureRefPrefix.length);
      final figure = _figures?[id];
      setState(() {
        _compoundId = null;
        _figureId = id;
        _args.clear();
        _useParams = figure == null
            ? null
            : userFigureDraftParams(figure.entry, figure.definition);
        _error = null;
      });
      return;
    }
    final id = value?.substring('compound:'.length);
    final picked = id == null ? null : _compounds?[id];
    setState(() {
      _compoundId = id;
      _figureId = null;
      _useParams = null;
      _args
        ..clear()
        ..addAll(
          picked == null
              ? const {}
              : previewArguments(picked.definition, contraTaxonomy) ?? const {},
        );
      _error = null;
    });
  }

  /// The token's problem, or null: shared by both kinds.
  String? _tokenError(AppLocalizations l10n, String token) {
    if (token.isEmpty) return l10n.shorthandEditorErrorEmpty;
    if (token.length > maxShorthandTokenLength) {
      return l10n.shorthandEditorErrorTooLong(maxShorthandTokenLength);
    }
    if (widget.existingTokens.contains(normalizeShorthandToken(token))) {
      return l10n.shorthandEditorErrorDuplicate(token);
    }
    return null;
  }

  void _save() {
    if (_figureId != null) return _saveUserFigure();
    final l10n = AppLocalizations.of(context);
    final token = _token.text.trim();
    String? error;
    final picked = _compoundId == null ? null : _compounds?[_compoundId];
    if (_tokenError(l10n, token) case final tokenError?) {
      error = tokenError;
    } else if (picked == null) {
      error = l10n.compoundShorthandEditorNoFigure;
    } else if (expandCompound(picked.definition, _args, contraTaxonomy) ==
        null) {
      error = l10n.compoundShorthandEditorInvalidValues;
    }
    final shorthand = picked == null
        ? null
        : CompoundShorthand(
            token: token,
            compoundId: picked.entry.id,
            compoundName: picked.entry.name,
            args: {
              for (final p in picked.definition.params)
                if (_args[p.key] case final Object value) p.key: value,
            },
          );
    // What is saved must survive the next load: a text value over the stored
    // bound would drop the whole shorthand then.
    if (error == null && !CompoundShorthands.keeps(shorthand!)) {
      error = l10n.compoundEditorTooLong;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(shorthand);
  }

  /// Saves a shorthand for a new figure (#1023): its arguments, and its beats
  /// only where they differ from the figure's default, so a change to the
  /// default reaches the shorthand.
  void _saveUserFigure() {
    final l10n = AppLocalizations.of(context);
    final token = _token.text.trim();
    final figure = _figures?[_figureId];
    final params = _useParams;
    UserFigureShorthand? shorthand;
    var error = _tokenError(l10n, token);
    if (error == null && (figure == null || params == null)) {
      error = l10n.compoundShorthandEditorNoFigure;
    }
    if (error == null) {
      final use = Figure(move: customMove, params: params!);
      final renders =
          FigureRenderer(
            contraTaxonomy,
            userFigures: UserFigureCatalog.fromEntries([figure!.entry]),
          ).renderUserFigureCanonical(use) !=
          null;
      final beats = params['beats'];
      shorthand = UserFigureShorthand(
        token: token,
        figureId: figure.entry.id,
        figureName: figure.entry.name,
        args: userFigureArgsOf(FigureDraft()..params.addAll(params)),
        beats: beats is int && beats != figure.definition.defaultBeats
            ? beats
            : null,
      );
      if (!renders) {
        error = l10n.compoundShorthandEditorInvalidValues;
      } else if (!UserFigureShorthands.keeps(shorthand)) {
        // What is saved must survive the next load.
        error = l10n.compoundEditorTooLong;
      }
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(shorthand);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final dialect = ActiveDialectScope.of(context);
    final compounds = _compounds;
    final figures = _figures;
    final picked = _compoundId == null ? null : compounds?[_compoundId];
    final pickedFigure = _figureId == null ? null : figures?[_figureId];
    final useParams = _useParams;
    // Both kinds in one list, by name: each is "one of your figures".
    final choices = <({String value, String name})>[
      if (compounds != null && figures != null) ...[
        for (final c in compounds.values)
          (value: _compoundValue(c.entry.id), name: c.entry.name),
        for (final f in figures.values)
          (value: _figureValue(f.entry.id), name: f.entry.name),
      ],
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final pickedValue = picked != null
        ? _compoundValue(picked.entry.id)
        : pickedFigure != null
        ? _figureValue(pickedFigure.entry.id)
        : null;
    final expanded = picked == null
        ? null
        : expandPlaceholder(
            CompoundPlaceholder(id: picked.entry.id, name: '', args: _args),
            (id) => compounds?[id]?.definition,
          );
    return DiscardChangesGuard(
      dirty: _dirty,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isNew
                ? l10n.shorthandEditorTitleNew
                : l10n.shorthandEditorTitleEdit,
          ),
          actions: [
            AppBarTextAction(
              key: const ValueKey('compound-shorthand-save'),
              label: l10n.commonSave,
              icon: Icons.check,
              onPressed: compounds == null || figures == null ? null : _save,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  key: const ValueKey('compound-shorthand-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            TextField(
              key: const ValueKey('compound-shorthand-token'),
              controller: _token,
              maxLength: maxShorthandTokenLength,
              autofocus: _isNew,
              // Always rebuilds, so the back guard sees the edited token.
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: l10n.shorthandEditorTokenLabel,
                helperText: l10n.shorthandEditorTokenHelper,
                border: const OutlineInputBorder(),
              ),
            ),
            // Warns, never blocks (#1827), for both kinds this editor saves.
            ShorthandShadowWarning(
              warningKey: const ValueKey('compound-shorthand-shadow-warning'),
              controller: _token,
            ),
            const SizedBox(height: 16),
            if (compounds != null && figures != null && choices.isEmpty)
              Text(
                l10n.compoundShorthandEditorNoCompounds,
                key: const ValueKey('compound-shorthand-none'),
              )
            else if (compounds != null && figures != null) ...[
              DropdownButtonFormField<String>(
                key: const ValueKey('compound-shorthand-compound'),
                initialValue: pickedValue,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.compoundShorthandEditorFigureLabel,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final choice in choices)
                    DropdownMenuItem(
                      key: ValueKey(
                        'compound-shorthand-choice-${choice.value}',
                      ),
                      value: choice.value,
                      child: Text(
                        _renderer.renderFreeText(choice.name, dialect),
                      ),
                    ),
                ],
                onChanged: _pick,
              ),
              if (pickedFigure != null && useParams != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: UserFigureUseEditor(
                    keyPrefix: 'user-figure-shorthand-arg',
                    params: useParams,
                    dialect: dialect,
                    onChanged: (next) => setState(() {
                      _useParams = next;
                      _error = null;
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l10n.userFigureEditorPreview(
                      UserFiguresScope.rendererOf(context).render(
                        Figure(move: customMove, params: useParams),
                        dialect,
                      ),
                    ),
                    key: const ValueKey('user-figure-shorthand-reads-as'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
              if (picked != null) ...[
                for (final param in picked.definition.params)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: CompoundArgumentEditor(
                      keyPrefix: 'compound-shorthand-arg',
                      definition: picked.definition,
                      param: param,
                      value: _args[param.key],
                      dialect: dialect,
                      onChanged: (value) => setState(() {
                        _args[param.key] = value;
                        _error = null;
                      }),
                    ),
                  ),
                if (expanded != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      l10n.danceEditorCompoundExpandsTo(
                        expanded.length,
                        CompoundDefinition.beatsOf(expanded, contraTaxonomy),
                      ),
                      key: const ValueKey('compound-shorthand-expands'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
