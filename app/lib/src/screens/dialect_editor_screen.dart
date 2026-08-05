import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/validation_issue_labels.dart';
import '../search/facet_labels.dart' show humanizeToken;

/// Full-screen term editor for a single named [Dialect] (`docs/design/ux.md`
/// §6). Edits the pieces a dialect can set — role terms (gendered terms live
/// here, not as presets), per-move substitutions (with the `%S` handedness
/// placeholder), dancer-token substitutions, and the discouraged-terms list —
/// then returns the edited [Dialect] via [Navigator.pop] (or `null` on cancel).
///
/// The dialect's [Dialect.name] is preserved unchanged; renaming is a separate
/// action in the dialect library so it can uniquify against presets/customs.
///
/// A live [_DialectPreview] renders representative sample figures through the
/// working dialect, and [Dialect.validate] runs on every edit so collision /
/// empty-substitution issues surface inline as the user types (the same check
/// still guards Save so an invalid dialect is never returned).
class DialectEditorScreen extends StatefulWidget {
  const DialectEditorScreen({super.key, required this.initial});

  /// The dialect being edited. Its name is kept as-is on save.
  final Dialect initial;

  @override
  State<DialectEditorScreen> createState() => _DialectEditorScreenState();
}

class _DialectEditorScreenState extends State<DialectEditorScreen> {
  final _role1Singular = TextEditingController();
  final _role1Plural = TextEditingController();
  final _role2Singular = TextEditingController();
  final _role2Plural = TextEditingController();
  final _discouragedInput = TextEditingController();

  /// One controller per move that currently has (or is being given) a
  /// substitution row, keyed by canonical move id.
  final Map<String, TextEditingController> _moveCtrls = {};

  /// One controller per dancer token that currently has (or is being given) a
  /// substitution row, keyed by canonical dancer token.
  final Map<String, TextEditingController> _dancerCtrls = {};

  List<String> _discouraged = const [];
  bool _showMoves = false;
  bool _showDancers = false;

  /// Model-level issues (empty/ambiguous substitutions) recomputed live on every
  /// edit via [Dialect.validate], surfaced inline so collisions show as the user
  /// types; the same check still guards Save so an invalid dialect is never
  /// returned.
  List<ValidationIssue> _issues = const [];

  /// The dialect assembled from the current editor state, kept in sync on every
  /// edit so the live preview and validation both read from it.
  late Dialect _working;

  @override
  void initState() {
    super.initState();
    _syncFrom(widget.initial);
    _working = _assemble();
    _issues = _working.validate();
  }

  void _syncFrom(Dialect d) {
    _role1Singular.text = d.roles['role1']?.singular ?? '';
    _role1Plural.text = d.roles['role1']?.plural ?? '';
    _role2Singular.text = d.roles['role2']?.singular ?? '';
    _role2Plural.text = d.roles['role2']?.plural ?? '';
    for (final c in _moveCtrls.values) {
      c.dispose();
    }
    _moveCtrls.clear();
    for (final entry in d.moves.entries) {
      _moveCtrls[entry.key] = TextEditingController(text: entry.value);
    }
    for (final c in _dancerCtrls.values) {
      c.dispose();
    }
    _dancerCtrls.clear();
    for (final entry in d.dancers.entries) {
      _dancerCtrls[entry.key] = TextEditingController(text: entry.value);
    }
    _discouraged = List.of(d.discouragedTerms);
  }

  @override
  void dispose() {
    _role1Singular.dispose();
    _role1Plural.dispose();
    _role2Singular.dispose();
    _role2Plural.dispose();
    _discouragedInput.dispose();
    for (final c in _moveCtrls.values) {
      c.dispose();
    }
    for (final c in _dancerCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Builds a [RoleTerm] from a singular/plural pair, or `null` when the
  /// singular is blank (the role is then dropped from the dialect).
  RoleTerm? _roleTerm(
    TextEditingController singular,
    TextEditingController plural,
  ) {
    final s = singular.text.trim();
    if (s.isEmpty) return null;
    final p = plural.text.trim();
    return RoleTerm(s, plural: p.isEmpty ? null : p);
  }

  /// Assembles the current editor state into a [Dialect], preserving the
  /// original name. Pure — no side effects — so it can feed both the live
  /// preview/validation ([_onEdited]) and the Save guard ([_save]).
  Dialect _assemble() {
    final roles = <String, RoleTerm>{};
    final r1 = _roleTerm(_role1Singular, _role1Plural);
    final r2 = _roleTerm(_role2Singular, _role2Plural);
    if (r1 != null) roles['role1'] = r1;
    if (r2 != null) roles['role2'] = r2;

    final moves = <String, String>{};
    for (final entry in _moveCtrls.entries) {
      final v = entry.value.text.trim();
      if (v.isNotEmpty) moves[entry.key] = v;
    }

    final dancers = <String, String>{};
    for (final entry in _dancerCtrls.entries) {
      final v = entry.value.text.trim();
      if (v.isNotEmpty) dancers[entry.key] = v;
    }

    return Dialect(
      name: widget.initial.name,
      roles: roles,
      moves: moves,
      dancers: dancers,
      discouragedTerms: _discouraged,
    );
  }

  /// Re-assembles the working dialect and recomputes validation issues on every
  /// edit, so the live preview and the inline collision/empty-substitution
  /// warnings update as the user types.
  void _onEdited() {
    setState(() {
      _working = _assemble();
      _issues = _working.validate();
    });
  }

  /// Returns the edited dialect to the caller. If the assembled dialect has
  /// validation issues (empty or ambiguous substitutions), they are surfaced
  /// inline and the editor stays open.
  void _save() {
    final edited = _assemble();
    final issues = edited.validate();
    if (issues.isNotEmpty) {
      setState(() {
        _working = edited;
        _issues = issues;
      });
      return;
    }
    Navigator.of(context).pop(edited);
  }

  void _addDiscouraged() {
    final term = _discouragedInput.text.trim().toLowerCase();
    if (term.isEmpty || _discouraged.contains(term)) {
      _discouragedInput.clear();
      return;
    }
    setState(() {
      _discouraged = [..._discouraged, term];
      _discouragedInput.clear();
    });
  }

  void _removeDiscouraged(String term) {
    setState(
      () => _discouraged = _discouraged.where((t) => t != term).toList(),
    );
  }

  void _restoreDiscouragedDefaults() {
    setState(() => _discouraged = List.of(Dialect.defaultDiscouragedTerms));
  }

  void _addMoveSubstitution(String moveId) {
    setState(() {
      _moveCtrls[moveId] = TextEditingController();
      _showMoves = true;
    });
  }

  void _removeMoveSubstitution(String moveId) {
    _moveCtrls.remove(moveId)?.dispose();
    _onEdited();
  }

  void _addDancerSubstitution(String token) {
    setState(() {
      _dancerCtrls[token] = TextEditingController();
      _showDancers = true;
    });
  }

  void _removeDancerSubstitution(String token) {
    _dancerCtrls.remove(token)?.dispose();
    _onEdited();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.dialectEditorTitle(widget.initial.name)),
        actions: [
          TextButton(
            key: const ValueKey('dialect-editor-save'),
            onPressed: _save,
            child: Text(l10n.commonSave),
          ),
        ],
      ),
      body: ListView(
        children: [
          if (_issues.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                _issues.map((i) => validationIssueMessage(l10n, i)).join('\n'),
                key: const ValueKey('dialect-validation-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          _EditorHeader(title: l10n.dialectEditorSectionRoleTerms),
          _RoleTermsEditor(
            role1Singular: _role1Singular,
            role1Plural: _role1Plural,
            role2Singular: _role2Singular,
            role2Plural: _role2Plural,
            onChanged: _onEdited,
          ),
          _EditorHeader(title: l10n.dialectEditorSectionMoveSubs),
          _MoveSubstitutionsEditor(
            controllers: _moveCtrls,
            expanded: _showMoves,
            onToggle: () => setState(() => _showMoves = !_showMoves),
            onEdited: _onEdited,
            onAdd: _addMoveSubstitution,
            onRemove: _removeMoveSubstitution,
          ),
          _EditorHeader(title: l10n.dialectEditorSectionDancerSubs),
          _DancerSubstitutionsEditor(
            controllers: _dancerCtrls,
            dialect: _working,
            expanded: _showDancers,
            onToggle: () => setState(() => _showDancers = !_showDancers),
            onEdited: _onEdited,
            onAdd: _addDancerSubstitution,
            onRemove: _removeDancerSubstitution,
          ),
          _EditorHeader(title: l10n.dialectEditorSectionDiscouraged),
          _DiscouragedTermsEditor(
            terms: _discouraged,
            input: _discouragedInput,
            onAdd: _addDiscouraged,
            onRemove: _removeDiscouraged,
            onRestoreDefaults: _restoreDiscouragedDefaults,
          ),
          _EditorHeader(title: l10n.dialectEditorSectionPreview),
          _DialectPreview(dialect: _working),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// Two-role editor: singular + plural for role1 and role2. Blank singular drops
/// the role (canonical). This is where a user enters gendered terms if wanted.
class _RoleTermsEditor extends StatelessWidget {
  const _RoleTermsEditor({
    required this.role1Singular,
    required this.role1Plural,
    required this.role2Singular,
    required this.role2Plural,
    required this.onChanged,
  });

  final TextEditingController role1Singular;
  final TextEditingController role1Plural;
  final TextEditingController role2Singular;
  final TextEditingController role2Plural;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _roleRow(
            context,
            label: l10n.dialectEditorRole1,
            singularKey: 'dialect-role1-singular',
            pluralKey: 'dialect-role1-plural',
            singular: role1Singular,
            plural: role1Plural,
          ),
          const SizedBox(height: 12),
          _roleRow(
            context,
            label: l10n.dialectEditorRole2,
            singularKey: 'dialect-role2-singular',
            pluralKey: 'dialect-role2-plural',
            singular: role2Singular,
            plural: role2Plural,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.dialectEditorRolesHelp,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _roleRow(
    BuildContext context, {
    required String label,
    required String singularKey,
    required String pluralKey,
    required TextEditingController singular,
    required TextEditingController plural,
  }) {
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text(label),
          ),
        ),
        Expanded(
          child: TextField(
            key: ValueKey(singularKey),
            controller: singular,
            decoration: InputDecoration(labelText: l10n.dialectEditorSingular),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            key: ValueKey(pluralKey),
            controller: plural,
            decoration: InputDecoration(labelText: l10n.dialectEditorPlural),
            onChanged: (_) => onChanged(),
          ),
        ),
      ],
    );
  }
}

/// Collapsible per-move substitution editor. Shows an editable/removable row
/// for each move that has a substitution, plus a dropdown to add one for any
/// other move. `%S` in a substitution injects the figure's handedness.
class _MoveSubstitutionsEditor extends StatelessWidget {
  const _MoveSubstitutionsEditor({
    required this.controllers,
    required this.expanded,
    required this.onToggle,
    required this.onEdited,
    required this.onAdd,
    required this.onRemove,
  });

  final Map<String, TextEditingController> controllers;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onEdited;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  static String _moveLabel(String id) =>
      contraTaxonomy.moves[id]?.displayName ?? id;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final overridden = controllers.keys.toList()
      ..sort(
        (a, b) =>
            _moveLabel(a).toLowerCase().compareTo(_moveLabel(b).toLowerCase()),
      );
    final available =
        [
          for (final m in contraTaxonomy.moves.values)
            if (m.id != customMoveId && !controllers.containsKey(m.id)) m.id,
        ]..sort(
          (a, b) => _moveLabel(
            a,
          ).toLowerCase().compareTo(_moveLabel(b).toLowerCase()),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('dialect-moves-toggle'),
              onPressed: onToggle,
              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              label: Text(
                overridden.isEmpty
                    ? l10n.dialectEditorMoveSubsAdd
                    : l10n.dialectEditorMoveSubsCount(overridden.length),
              ),
            ),
          ),
          if (expanded) ...[
            for (final id in overridden)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        _moveLabel(id),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        key: ValueKey('dialect-move-$id'),
                        controller: controllers[id],
                        decoration: InputDecoration(
                          labelText: _moveLabel(id),
                          hintText: l10n.dialectEditorMoveSubHint,
                        ),
                        onChanged: (_) => onEdited(),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('dialect-move-delete-$id'),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: l10n.commonRemove,
                      onPressed: () => onRemove(id),
                    ),
                  ],
                ),
              ),
            if (available.isNotEmpty)
              DropdownButton<String>(
                key: const ValueKey('dialect-add-move'),
                hint: Text(l10n.dialectEditorAddMove),
                value: null,
                isExpanded: true,
                items: [
                  for (final id in available)
                    DropdownMenuItem<String>(
                      value: id,
                      child: Text(_moveLabel(id)),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) onAdd(id);
                },
              ),
          ],
        ],
      ),
    );
  }
}

/// Editable dancer-substitution list, parallel to [_MoveSubstitutionsEditor].
/// Enumerates the whole dancer vocabulary — the positional/relational sets AND
/// the single-dancer identities (`onesRole1` … `twosRole2`) — minus the
/// role-driven `role1s`/`role2s`, which flow through role-term substitution
/// instead, and lets the caller override each with preferred wording.
///
/// The single-dancer identities were absent until issue #832 purely because
/// this iterated [ParamVocab.pairDancerSets] rather than the full
/// [ParamVocab.dancerSets]; there was no reason to exclude them, and they are
/// exactly the tokens a caller is most likely to want reworded ("robin two"
/// rather than the default "second robin").
class _DancerSubstitutionsEditor extends StatelessWidget {
  const _DancerSubstitutionsEditor({
    required this.controllers,
    required this.dialect,
    required this.expanded,
    required this.onToggle,
    required this.onEdited,
    required this.onAdd,
    required this.onRemove,
  });

  final Map<String, TextEditingController> controllers;

  /// The dialect as currently edited, so a row label tracks the role terms the
  /// caller is typing (`onesRole1` reads "first lark" the moment role1 becomes
  /// "lark").
  final Dialect dialect;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onEdited;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  /// The substitutable dancer tokens: the whole dancer vocabulary — group sets
  /// and single-dancer identities alike — minus the role-driven
  /// `role1s`/`role2s`, which are handled by role-term substitution rather than
  /// here.
  static final List<String> _substitutableTokens = [
    for (final t in ParamVocab.dancerSets)
      if (t != 'role1s' && t != 'role2s') t,
  ];

  /// Human-readable label for a dancer token: the single-dancer identities read
  /// as their dialect-aware default (`twosRole2` -> "second robin"), everything
  /// else humanizes its camelCase (`nextNeighbors` -> `next neighbors`).
  ///
  /// The default, NOT [Dialect.dancers]-aware: the label names the token being
  /// overridden, so echoing the substitution the caller is typing into the
  /// adjacent field would leave the row self-referential. Without the
  /// single-dancer branch this screen would show the raw `twos role2` that
  /// issue #832 is about, in the very UI that fixes it.
  String _dancerLabel(String token) =>
      FigureRenderer.singleDancerDefaultTerm(token, dialect) ??
      humanizeToken(token);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final overridden = controllers.keys.toList()
      ..sort(
        (a, b) => _dancerLabel(
          a,
        ).toLowerCase().compareTo(_dancerLabel(b).toLowerCase()),
      );
    final available =
        [
          for (final token in _substitutableTokens)
            if (!controllers.containsKey(token)) token,
        ]..sort(
          (a, b) => _dancerLabel(
            a,
          ).toLowerCase().compareTo(_dancerLabel(b).toLowerCase()),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('dialect-dancers-toggle'),
              onPressed: onToggle,
              icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              label: Text(
                overridden.isEmpty
                    ? l10n.dialectEditorDancerSubsAdd
                    : l10n.dialectEditorDancerSubsCount(overridden.length),
              ),
            ),
          ),
          if (expanded) ...[
            for (final token in overridden)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        _dancerLabel(token),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        key: ValueKey('dialect-dancer-$token'),
                        controller: controllers[token],
                        decoration: InputDecoration(
                          labelText: _dancerLabel(token),
                          hintText: l10n.dialectEditorDancerSubHint,
                        ),
                        onChanged: (_) => onEdited(),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('dialect-dancer-delete-$token'),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: l10n.commonRemove,
                      onPressed: () => onRemove(token),
                    ),
                  ],
                ),
              ),
            if (available.isNotEmpty)
              DropdownButton<String>(
                key: const ValueKey('dialect-add-dancer'),
                hint: Text(l10n.dialectEditorAddDancerTerm),
                value: null,
                isExpanded: true,
                items: [
                  for (final token in available)
                    DropdownMenuItem<String>(
                      value: token,
                      child: Text(_dancerLabel(token)),
                    ),
                ],
                onChanged: (token) {
                  if (token != null) onAdd(token);
                },
              ),
          ],
        ],
      ),
    );
  }
}

/// Editable discouraged-terms list: chips with delete, an add field, and a
/// "restore defaults" action. Terms are user data (never blocked), lowercased.
class _DiscouragedTermsEditor extends StatelessWidget {
  const _DiscouragedTermsEditor({
    required this.terms,
    required this.input,
    required this.onAdd,
    required this.onRemove,
    required this.onRestoreDefaults,
  });

  final List<String> terms;
  final TextEditingController input;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
  final VoidCallback onRestoreDefaults;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.dialectEditorDiscouragedHelp,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (terms.isEmpty)
            Text(l10n.dialectEditorDiscouragedEmpty)
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final term in terms)
                  Chip(
                    key: ValueKey('dialect-discouraged-chip-$term'),
                    label: Text(term),
                    onDeleted: () => onRemove(term),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('dialect-discouraged-add'),
                  controller: input,
                  decoration: InputDecoration(
                    labelText: l10n.dialectEditorAddTermLabel,
                    isDense: true,
                  ),
                  onSubmitted: (_) => onAdd(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const ValueKey('dialect-discouraged-add-button'),
                icon: const Icon(Icons.add),
                tooltip: l10n.dialectEditorAddTermTooltip,
                onPressed: onAdd,
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('dialect-discouraged-restore'),
              onPressed: onRestoreDefaults,
              child: Text(l10n.dialectEditorRestoreDefaults),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live, read-only preview of a small fixed set of representative sample
/// figures rendered through the working [dialect] via [FigureRenderer]. Chosen
/// to exercise the substitutions this editor controls — a role-term plural
/// ([allemande] with `role1s`), a dancer term + move substitution ([swing] with
/// `partners`, [do_si_do] with `neighbors`), and a role term inside free-text
/// prose — so edits visibly update as the user types. Deterministic and
/// dialect-only; nothing is persisted.
class _DialectPreview extends StatelessWidget {
  const _DialectPreview({required this.dialect});

  final Dialect dialect;

  static final FigureRenderer _renderer = FigureRenderer(contraTaxonomy);

  static final List<Figure> _sampleFigures = [
    Figure(
      move: 'allemande',
      params: const {'who': 'role1s', 'hand': 'left', 'turn': 1.5},
    ),
    Figure(move: 'swing', params: const {'who': 'partners'}),
    Figure(move: 'do_si_do', params: const {'who': 'neighbors'}),
  ];

  static const String _sampleFreeText = 'role1s scoop up their role2 and swing';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final lines = <String>[
      for (final figure in _sampleFigures) _renderer.render(figure, dialect),
      _renderer.renderFreeText(_sampleFreeText, dialect),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.dialectEditorPreviewHelp, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                key: const ValueKey('dialect-preview'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(line, style: theme.textTheme.bodyMedium),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
