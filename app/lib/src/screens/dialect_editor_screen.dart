import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/user_figures_scope.dart';
import '../data/validation_issue_labels.dart';
import '../search/facet_labels.dart' show humanizeToken;
import '../theme/destructive_button_style.dart';
import '../widgets/collapsible_section.dart';
import '../widgets/confirm_discard_changes.dart';
import '../widgets/wording_condition_notes.dart';
import '../widgets/app_bar_text_action.dart';

/// Full-screen term editor for a single named [Dialect] (`docs/design/ux.md`
/// §6). Edits the pieces a dialect can set — role terms (gendered terms live
/// here, not as presets), per-move substitutions (with the `%S` handedness
/// placeholder), display-only per-move wording templates, dancer-token
/// substitutions, and the discouraged-terms list — then returns the edited
/// [Dialect] via [Navigator.pop] (or `null` on cancel).
///
/// The dialect's [Dialect.name] is preserved unchanged; renaming is a separate
/// action in the dialect library so it can uniquify against presets/customs.
///
/// A live [_DialectPreview] renders representative sample figures through the
/// working dialect. [Dialect.validate] and the move-wording template validator
/// run on every edit so substitution and wording issues surface inline as the
/// user types; both checks also guard Save so invalid data is never returned.
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
  final Map<String, TextEditingController> _wordingCtrls = {};
  final Map<String, Map<String, TextEditingController>> _branchWordingCtrls =
      {};

  /// One controller per dancer token that currently has (or is being given) a
  /// substitution row, keyed by canonical dancer token.
  final Map<String, TextEditingController> _dancerCtrls = {};

  List<String> _discouraged = const [];
  bool _showRoles = true;
  bool _showMoves = false;
  bool _showWordings = false;
  bool _showDancers = false;
  bool _showDiscouraged = false;

  /// Model-level substitution issues recomputed live on every edit via
  /// [Dialect.validate], surfaced inline so collisions show as the user types.
  /// Move-wording syntax/length issues are tracked separately because valid
  /// missing-slot templates have a distinct confirmation flow.
  List<ValidationIssue> _issues = const [];

  /// The keys of the wordings that can't be read, labelled when shown (a
  /// figure of your own's label reads inherited widgets, which can't be read
  /// before the first build).
  List<String> _invalidMoveWordings = const [];

  /// The dialect assembled from the current editor state, kept in sync on every
  /// edit so the live preview and validation both read from it.
  late Dialect _working;

  static final FigureRenderer _renderer = FigureRenderer(contraTaxonomy);

  bool _seeded = false;

  /// Each wording as the editor showed it from its stored form, under
  /// [_wordingKey]: one still as shown is kept as stored and not read again
  /// ([_keptWording]), so a wording for a figure not on this device, or one
  /// saved before conditions whose brackets start with "if", stays as it was.
  final Map<String, ({String stored, String shown})> _shownWordings = {};

  /// Each wording as last typed and read, with its stored form: what it
  /// means, so it keeps that meaning while the words it was written in
  /// change ([_trackWordings], [_reshowWordings]).
  final Map<String, ({String stored, String shown})> _readWordings = {};

  /// Seeds the editor on first use rather than in initState: a wording for a
  /// figure of your own is shown with its conditions in words, which needs
  /// the user's figures, an inherited widget initState can't read. When the
  /// figures change later (they load after the editor may open), a wording
  /// for one still as first shown is shown again in their words.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) {
      _reshowWordings(figuresOnly: true);
      return;
    }
    _seeded = true;
    _syncFrom(widget.initial);
    _working = _assemble();
    _issues = _working.validate();
    _invalidMoveWordings = _invalidMoveWordingKeys();
  }

  /// The key a wording is kept under: a move or figure, and a branch.
  static String _wordingKey(String id, [String? branch]) =>
      branch == null ? id : '$id$_branchSeparator$branch';

  /// What joins a move and a branch in a [_wordingKey]: a character no key
  /// or branch holds.
  static const String _branchSeparator = '\u0000';

  /// Forgets what the editor showed and read for the wording [id], any
  /// branch included: a wording added again starts afresh.
  void _forgetWording(String id) {
    bool isOf(String key) =>
        key == id || key.startsWith('$id$_branchSeparator');
    _shownWordings.removeWhere((key, _) => isOf(key));
    _readWordings.removeWhere((key, _) => isOf(key));
  }

  /// [stored], the wording [id] as a dialect stores it, as the editor shows
  /// it: its conditions in [dialect]'s words.
  String _shownWording(String id, String stored, Dialect dialect) =>
      wordingForEditing(
        stored,
        _wordingVocabulary(id, dialect, UserFiguresScope.catalogOf(context)),
      );

  /// A controller showing the stored wording [stored] for [id] (and
  /// [branch]) in [dialect]'s words, remembered as shown.
  TextEditingController _wordingController(
    String id,
    String stored,
    Dialect dialect, [
    String? branch,
  ]) {
    final shown = _shownWording(id, stored, dialect);
    _shownWordings[_wordingKey(id, branch)] = (stored: stored, shown: shown);
    return TextEditingController(text: shown);
  }

  /// The stored form of the wording under [key] when [text] is still as the
  /// editor showed it, else null: it is then read again.
  String? _keptWording(String key, String text) {
    final shown = _shownWordings[key];
    if (shown == null || shown.shown.trim() != text.trim()) return null;
    // A stored wording that doesn't read is reported, as it always was.
    if (!FigureRenderer.isValidMoveWordingTemplate(shown.stored)) return null;
    // Kept while its conditions still fit what it may test, or nothing can
    // be tested here (a figure not on this device): once one tests what a
    // figure no longer has, it is read again, to say which.
    final nodes = parseStoredWording(shown.stored);
    // What it may test doesn't depend on the dialect's words.
    final vocabulary = _wordingVocabulary(
      key.split(_branchSeparator).first,
      Dialect.canonical,
      UserFiguresScope.catalogOf(context),
    );
    if (nodes != null &&
        vocabulary.names.isNotEmpty &&
        !wordingConditionsFit(nodes, vocabulary.subjects)) {
      return null;
    }
    return shown.stored;
  }

  /// Remembers each wording that reads in [words], the words it was typed
  /// in, as its stored form with its text, so it keeps that meaning
  /// however the words change next ([_reshowWordings]).
  void _trackWordings(Dialect words) {
    final userFigures = UserFiguresScope.catalogOf(context);
    void track(String id, TextEditingController controller, [String? branch]) {
      final key = _wordingKey(id, branch);
      if (controller.text.trim().isEmpty ||
          _keptWording(key, controller.text) != null) {
        return;
      }
      final stored = _checkWording(
        id,
        controller.text,
        words,
        userFigures,
      ).stored;
      if (stored != null) {
        _readWordings[key] = (stored: stored, shown: controller.text);
      }
    }

    for (final entry in _wordingCtrls.entries) {
      track(entry.key, entry.value);
    }
    for (final moveEntry in _branchWordingCtrls.entries) {
      for (final branchEntry in moveEntry.value.entries) {
        track(moveEntry.key, branchEntry.value, branchEntry.key);
      }
    }
  }

  /// Shows every wording with a condition again, from what it means, in the
  /// words the editor now holds (or, with [figuresOnly], each figure of your
  /// own's in its figure's): a role or dancer renamed, or two swapped, never
  /// changes what a condition tests. One that doesn't read stays as typed.
  void _reshowWordings({bool figuresOnly = false}) {
    final now = _wordsNow();
    void reshow(String id, TextEditingController controller, [String? branch]) {
      if (figuresOnly && !isUserFigureKey(id)) return;
      final key = _wordingKey(id, branch);
      final kept = _keptWording(key, controller.text);
      final read = _readWordings[key];
      final stored =
          kept ??
          (!figuresOnly && read != null && read.shown == controller.text
              ? read.stored
              : null);
      if (stored == null) return;
      final nodes = parseStoredWording(stored);
      if (nodes == null || !wordingHasConditions(nodes)) return;
      final shown = _shownWording(id, stored, now);
      if (kept != null) _shownWordings[key] = (stored: stored, shown: shown);
      _readWordings[key] = (stored: stored, shown: shown);
      if (controller.text != shown) controller.text = shown;
    }

    for (final entry in _wordingCtrls.entries) {
      reshow(entry.key, entry.value);
    }
    for (final moveEntry in _branchWordingCtrls.entries) {
      for (final branchEntry in moveEntry.value.entries) {
        reshow(moveEntry.key, branchEntry.value, branchEntry.key);
      }
    }
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
    for (final c in _wordingCtrls.values) {
      c.dispose();
    }
    _wordingCtrls.clear();
    _shownWordings.clear();
    _readWordings.clear();
    for (final entry in d.moveWordings.entries) {
      _wordingCtrls[entry.key] = _wordingController(entry.key, entry.value, d);
    }
    for (final branches in _branchWordingCtrls.values) {
      for (final c in branches.values) {
        c.dispose();
      }
    }
    _branchWordingCtrls.clear();
    for (final moveId in d.moveWordingBranches.keys) {
      final branches = <String, TextEditingController>{};
      for (final branch in _renderer.moveWordingBranchIds(moveId)) {
        branches[branch] = _wordingController(
          moveId,
          d.moveWordingBranches[moveId]?[branch] ?? '',
          d,
          branch,
        );
      }
      if (branches.isNotEmpty) _branchWordingCtrls[moveId] = branches;
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
    for (final c in _wordingCtrls.values) {
      c.dispose();
    }
    for (final branches in _branchWordingCtrls.values) {
      for (final c in branches.values) {
        c.dispose();
      }
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

    // A wording still as shown is kept as stored; an edited one is read in
    // the words of the dialect as now edited and kept in its stored form, a
    // condition by meaning. One that can't be read is left out, so the
    // preview reads the normal wording, and reported under its field
    // ([_invalidMoveWordingKeys]).
    final words = Dialect(
      name: widget.initial.name,
      roles: roles,
      moves: moves,
      dancers: dancers,
    );
    final userFigures = UserFiguresScope.catalogOf(context);
    String? stored(String id, String text, [String? branch]) =>
        _keptWording(_wordingKey(id, branch), text) ??
        _checkWording(id, text, words, userFigures).stored;

    final moveWordings = <String, String>{};
    for (final entry in _wordingCtrls.entries) {
      final v = entry.value.text.trim();
      final kept = v.isEmpty ? null : stored(entry.key, v);
      if (kept != null) moveWordings[entry.key] = kept;
    }

    final moveWordingBranches = <String, Map<String, String>>{};
    for (final moveEntry in _branchWordingCtrls.entries) {
      final branches = <String, String>{};
      for (final branchEntry in moveEntry.value.entries) {
        final v = branchEntry.value.text.trim();
        final kept = v.isEmpty
            ? null
            : stored(moveEntry.key, v, branchEntry.key);
        if (kept != null) branches[branchEntry.key] = kept;
      }
      if (branches.isNotEmpty) {
        moveWordingBranches[moveEntry.key] = branches;
      }
    }

    return Dialect(
      name: widget.initial.name,
      roles: roles,
      moves: moves,
      moveWordings: moveWordings,
      moveWordingBranches: moveWordingBranches,
      dancers: dancers,
      discouragedTerms: _discouraged,
    );
  }

  /// Re-assembles the working dialect and recomputes validation issues on every
  /// edit, so the live preview and the inline collision/empty-substitution
  /// warnings update as the user types.
  void _onEdited() {
    // A wording just typed reads in the words it was typed in; renamed role
    // or dancer words then show every wording in them, as it still means.
    _trackWordings(_working);
    final now = _wordsNow();
    if (!mapEquals(now.roles, _working.roles) ||
        !mapEquals(now.dancers, _working.dancers)) {
      _reshowWordings();
    }
    setState(() {
      _working = _assemble();
      _issues = _working.validate();
      _invalidMoveWordings = _invalidMoveWordingKeys();
    });
  }

  /// The keys of the wordings, as typed, that can't be saved: each one's
  /// first error is shown under it ([_checkWording]). A wording still as
  /// shown is kept as stored, and not read again.
  List<String> _invalidMoveWordingKeys() {
    final userFigures = UserFiguresScope.catalogOf(context);
    bool invalid(String id, String text, [String? branch]) =>
        text.trim().isNotEmpty &&
        _keptWording(_wordingKey(id, branch), text) == null &&
        _checkWording(id, text, _working, userFigures).hasErrors;
    return [
      for (final entry in _wordingCtrls.entries)
        if (invalid(entry.key, entry.value.text)) entry.key,
      for (final entry in _branchWordingCtrls.entries)
        if (entry.value.entries.any(
          (b) => invalid(entry.key, b.value.text, b.key),
        ))
          entry.key,
    ];
  }

  /// The words the editor now holds: role terms, move names and dancer
  /// words, which a wording's values are read in.
  Dialect _wordsNow() {
    final roles = <String, RoleTerm>{};
    final r1 = _roleTerm(_role1Singular, _role1Plural);
    final r2 = _roleTerm(_role2Singular, _role2Plural);
    if (r1 != null) roles['role1'] = r1;
    if (r2 != null) roles['role2'] = r2;
    return Dialect(
      name: widget.initial.name,
      roles: roles,
      dancers: {
        for (final entry in _dancerCtrls.entries)
          if (entry.value.text.trim().isNotEmpty)
            entry.key: entry.value.text.trim(),
      },
    );
  }

  Map<String, String> _incompleteMoveWordings(Dialect dialect) {
    final incomplete = <String, String>{};
    for (final entry in dialect.moveWordings.entries) {
      if (!FigureRenderer.isValidMoveWordingTemplate(entry.value)) continue;
      final missing =
          _renderer
              .moveWordingErrorMissingSlots(entry.key, entry.value)
              .toList()
            ..sort();
      if (missing.isNotEmpty) {
        incomplete[_label(entry.key)] = _renderer
            .moveWordingSlotLabels(entry.key, missing)
            .join(', ');
      }
    }
    return incomplete;
  }

  Map<String, String> _incompleteBranchWordings(
    Dialect dialect,
    AppLocalizations l10n,
  ) {
    final incomplete = <String, String>{};
    for (final moveEntry in dialect.moveWordingBranches.entries) {
      for (final branchEntry in moveEntry.value.entries) {
        final wording = branchEntry.value;
        final missing =
            _renderer
                .moveWordingBranchMissingSlots(
                  moveEntry.key,
                  branchEntry.key,
                  wording,
                )
                .toList()
              ..sort();
        if (missing.isNotEmpty ||
            !FigureRenderer.isValidMoveWordingTemplate(wording)) {
          final label = l10n.dialectEditorMoveWordingsConditionalLabel(
            '${_label(moveEntry.key)}: ${_branchLabel(branchEntry.key, l10n)}',
          );
          incomplete[label] = missing.isEmpty
              ? l10n.dialectEditorMoveWordingInvalid
              : _renderer
                    .moveWordingSlotLabels(moveEntry.key, missing)
                    .join(', ');
        }
      }
    }
    return incomplete;
  }

  /// [dialect] without a wording for one of the user's figures that is just
  /// the figure's own (#1023): such a copy would freeze it, so a later edit to
  /// the figure's wording would not reach this dialect.
  Dialect _withoutOwnWordings(Dialect dialect) {
    final userFigures = UserFiguresScope.catalogOf(context);
    final own = [
      for (final MapEntry(:key, :value) in dialect.moveWordings.entries)
        if (isUserFigureKey(key) &&
            userFigures[key.substring(userFigureRefPrefix.length)]
                    ?.definition
                    ?.template
                    .trim() ==
                value.trim())
          key,
    ];
    if (own.isEmpty) return dialect;
    return dialect.copyWith(
      moveWordings: {...dialect.moveWordings}
        ..removeWhere((key, _) => own.contains(key)),
    );
  }

  /// Returns the edited dialect to the caller. If the assembled dialect has
  /// validation issues (empty or ambiguous substitutions), they are surfaced
  /// inline and the editor stays open. Templates that omit available slots are
  /// saved only after the user confirms the affected figures.
  Future<void> _save() async {
    final edited = _withoutOwnWordings(_assemble());
    final issues = edited.validate();
    _working = edited;
    final invalidMoveWordings = _invalidMoveWordingKeys();
    if (invalidMoveWordings.isNotEmpty) {
      setState(() {
        _working = edited;
        _issues = issues;
        _invalidMoveWordings = invalidMoveWordings;
      });
      return;
    }
    if (issues.isNotEmpty) {
      setState(() {
        _working = edited;
        _issues = issues;
        _invalidMoveWordings = invalidMoveWordings;
      });
      return;
    }
    final incomplete = _incompleteMoveWordings(edited);
    final incompleteBranches = _incompleteBranchWordings(
      edited,
      AppLocalizations.of(context),
    );
    if (incompleteBranches.isNotEmpty) {
      setState(() {
        _working = edited;
        _issues = issues;
      });
      return;
    }
    if (incomplete.isNotEmpty) {
      final details = incomplete.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');
      final l10n = AppLocalizations.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('dialect-wording-confirm-dialog'),
          title: Text(l10n.dialectEditorMoveWordingConfirmTitle),
          content: SingleChildScrollView(
            child: Text(l10n.dialectEditorMoveWordingConfirmBody(details)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              key: const ValueKey('dialect-wording-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    if (!mounted) return;
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

  Future<void> _confirmRestoreDiscouragedDefaults() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('dialect-discouraged-reset-dialog'),
        title: Text(l10n.dialectEditorDiscouragedResetTitle),
        content: Text(l10n.dialectEditorDiscouragedResetBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('dialect-discouraged-reset-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.dialectEditorRestoreDefaults),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _restoreDiscouragedDefaults();
  }

  void _addMoveSubstitution(String moveId) {
    setState(() {
      _moveCtrls[moveId] = TextEditingController();
    });
  }

  void _removeMoveSubstitution(String moveId) {
    _moveCtrls.remove(moveId)?.dispose();
    _onEdited();
  }

  /// A move's label, or a figure of your own's name (#1023).
  String _label(String id) => _entryLabel(
    id,
    UserFiguresScope.catalogOf(context),
    _working,
    AppLocalizations.of(context),
    _renderer,
  );

  /// The keys of the user's figures a dialect can name or word, while Custom
  /// Figures is on (#1023): each one whose definition decodes, by name.
  List<String> _userFigureKeys() {
    final catalog = UserFiguresScope.shownCatalogOf(context);
    return [
      for (final view in catalog.figures)
        if (view.definition != null) userFigureKeyFor(view.id),
    ]..sort(
      (a, b) => _label(a).toLowerCase().compareTo(_label(b).toLowerCase()),
    );
  }

  void _addMoveWording(String moveId) {
    if (isUserFigureKey(moveId)) {
      // A figure of your own starts from its own wording.
      final view = UserFiguresScope.catalogOf(
        context,
      )[moveId.substring(userFigureRefPrefix.length)];
      setState(() {
        _wordingCtrls[moveId] = _wordingController(
          moveId,
          view?.definition?.template ?? '',
          _working,
        );
      });
      _onEdited();
      return;
    }
    setState(() {
      final branches = _renderer.moveWordingBranchIds(moveId);
      if (branches.isEmpty) {
        _wordingCtrls[moveId] = TextEditingController(
          text: _renderer.moveWordingTemplate(moveId) ?? '',
        );
      } else {
        _branchWordingCtrls[moveId] = {
          for (final branch in branches)
            branch: TextEditingController(
              text: _renderer.moveWordingBranchTemplate(moveId, branch) ?? '',
            ),
        };
      }
      _working = _assemble();
      _issues = _working.validate();
      _invalidMoveWordings = _invalidMoveWordingKeys();
    });
  }

  void _removeMoveWording(String moveId) {
    _wordingCtrls.remove(moveId)?.dispose();
    _forgetWording(moveId);
    _onEdited();
  }

  void _removeBranchMoveWording(String moveId) {
    final controllers = _branchWordingCtrls.remove(moveId);
    _forgetWording(moveId);
    if (controllers != null) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
    _onEdited();
  }

  void _restoreMoveWordings() {
    setState(() {
      for (final c in _wordingCtrls.values) {
        c.dispose();
      }
      _wordingCtrls.clear();
      for (final branches in _branchWordingCtrls.values) {
        for (final c in branches.values) {
          c.dispose();
        }
      }
      _branchWordingCtrls.clear();
      _shownWordings.clear();
      _readWordings.clear();
      _working = _assemble();
      _issues = _working.validate();
      _invalidMoveWordings = _invalidMoveWordingKeys();
    });
  }

  Future<void> _confirmRestoreMoveWordings() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('dialect-wordings-reset-dialog'),
        title: Text(l10n.dialectEditorMoveWordingsResetTitle),
        content: Text(l10n.dialectEditorMoveWordingsResetBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            style: destructiveFilledButtonStyle(
              Theme.of(dialogContext).colorScheme,
            ),
            key: const ValueKey('dialect-wordings-reset-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.dialectEditorMoveWordingsReset),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _restoreMoveWordings();
  }

  void _addDancerSubstitution(String token) {
    setState(() {
      _dancerCtrls[token] = TextEditingController();
    });
  }

  void _removeDancerSubstitution(String token) {
    _dancerCtrls.remove(token)?.dispose();
    _onEdited();
  }

  bool get _isDirty => _assemble() != widget.initial;

  Future<void> _confirmExit() async {
    final l10n = AppLocalizations.of(context);
    final choice = await confirmDiscardChanges(
      context,
      dialogKey: const ValueKey('dialect-exit-dialog'),
      title: l10n.dialectEditorExitTitle,
      message: l10n.dialectEditorExitBody,
      keepEditingLabel: l10n.commonCancel,
      discardLabel: l10n.dialectEditorExitWithoutSaving,
      discardKey: const ValueKey('dialect-exit-without-saving'),
      saveLabel: l10n.dialectEditorSaveAndExit,
      saveKey: const ValueKey('dialect-exit-save'),
    );
    if (!mounted) return;
    switch (choice) {
      case DiscardChangesChoice.save:
        await _save();
      case DiscardChangesChoice.discard:
        Navigator.of(context).pop();
      case DiscardChangesChoice.keepEditing:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final itemBuilders = _editorItemBuilders(l10n);
    return PopScope<Dialect>(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.dialectEditorTitle(widget.initial.name)),
          actions: [
            AppBarTextAction(
              key: const ValueKey('dialect-editor-save'),
              label: l10n.commonSave,
              icon: Icons.check,
              onPressed: _save,
            ),
          ],
        ),
        body: ListView.builder(
          itemCount: itemBuilders.length,
          itemBuilder: (context, index) => itemBuilders[index](),
        ),
      ),
    );
  }

  List<Widget Function()> _editorItemBuilders(AppLocalizations l10n) => [
    if (_issues.isNotEmpty || _invalidMoveWordings.isNotEmpty)
      () => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
          [
            ..._issues.map(
              (i) => validationIssueMessage(
                l10n,
                i,
                // Only a figure of your own's key is renamed: the other
                // messages name moves and roles as they always have.
                keyLabel: (key) => isUserFigureKey(key) ? _label(key) : key,
              ),
            ),
            if (_invalidMoveWordings.isNotEmpty)
              l10n.dialectEditorMoveWordingSaveError(
                _invalidMoveWordings.map(_label).join(', '),
              ),
          ].join('\n'),
          key: const ValueKey('dialect-validation-error'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    () => CollapsibleSection(
      sectionKey: const ValueKey('dialect-roles-toggle'),
      title: l10n.dialectEditorSectionRoleTerms,
      expanded: _showRoles,
      onExpansionChanged: (expanded) => setState(() => _showRoles = expanded),
      child: _RoleTermsEditor(
        role1Singular: _role1Singular,
        role1Plural: _role1Plural,
        role2Singular: _role2Singular,
        role2Plural: _role2Plural,
        onChanged: _onEdited,
      ),
    ),
    () => CollapsibleSection(
      sectionKey: const ValueKey('dialect-moves-toggle'),
      title: l10n.dialectEditorSectionMoveSubs,
      expanded: _showMoves,
      onExpansionChanged: (expanded) => setState(() => _showMoves = expanded),
      child: _MoveSubstitutionsEditor(
        label: _label,
        userFigureKeys: _userFigureKeys(),
        controllers: _moveCtrls,
        onEdited: _onEdited,
        onAdd: _addMoveSubstitution,
        onRemove: _removeMoveSubstitution,
      ),
    ),
    () => CollapsibleSection(
      sectionKey: const ValueKey('dialect-dancers-toggle'),
      title: l10n.dialectEditorSectionDancerSubs,
      expanded: _showDancers,
      onExpansionChanged: (expanded) => setState(() => _showDancers = expanded),
      child: _DancerSubstitutionsEditor(
        controllers: _dancerCtrls,
        dialect: _working,
        onEdited: _onEdited,
        onAdd: _addDancerSubstitution,
        onRemove: _removeDancerSubstitution,
      ),
    ),
    () => CollapsibleSection(
      sectionKey: const ValueKey('dialect-wordings-toggle'),
      title: l10n.dialectEditorSectionMoveWordings,
      expanded: _showWordings,
      onExpansionChanged: (expanded) =>
          setState(() => _showWordings = expanded),
      child: _MoveWordingsEditor(
        keptWording: _keptWording,
        label: _label,
        userFigureKeys: _userFigureKeys(),
        userFigures: UserFiguresScope.catalogOf(context),
        controllers: _wordingCtrls,
        branchControllers: _branchWordingCtrls,
        dialect: _working,
        onEdited: _onEdited,
        onAdd: _addMoveWording,
        onRemove: _removeMoveWording,
        onRemoveBranch: _removeBranchMoveWording,
        onRestoreDefaults: _confirmRestoreMoveWordings,
      ),
    ),
    () => CollapsibleSection(
      sectionKey: const ValueKey('dialect-discouraged-toggle'),
      title: l10n.dialectEditorSectionDiscouraged,
      expanded: _showDiscouraged,
      onExpansionChanged: (expanded) =>
          setState(() => _showDiscouraged = expanded),
      child: _DiscouragedTermsEditor(
        terms: _discouraged,
        input: _discouragedInput,
        onAdd: _addDiscouraged,
        onRemove: _removeDiscouraged,
        onRestoreDefaults: _confirmRestoreDiscouragedDefaults,
      ),
    ),
    () => _EditorHeader(title: l10n.dialectEditorSectionPreview),
    () => _DialectPreview(dialect: _working),
    () => const SizedBox(height: 24),
  ];
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
        title.toUpperCase(),
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
    required this.label,
    required this.userFigureKeys,
    required this.controllers,
    required this.onEdited,
    required this.onAdd,
    required this.onRemove,
  });

  final Map<String, TextEditingController> controllers;
  final VoidCallback onEdited;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  /// A move's label, or a figure of your own's name.
  final String Function(String id) label;

  /// The user's figures that can be named (#1023), offered after the moves.
  final List<String> userFigureKeys;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final overridden = controllers.keys.toList().reversed;
    final available = [
      for (final m in contraTaxonomy.moves.values)
        if (m.id != customMoveId && !controllers.containsKey(m.id)) m.id,
    ]..sort((a, b) => label(a).toLowerCase().compareTo(label(b).toLowerCase()));
    available.addAll([
      for (final key in userFigureKeys)
        if (!controllers.containsKey(key)) key,
    ]);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (available.isNotEmpty)
            DropdownButton<String>(
              key: const ValueKey('dialect-add-move'),
              hint: Text(
                l10n.dialectEditorAddMove,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              value: null,
              isExpanded: true,
              iconEnabledColor: Theme.of(context).colorScheme.secondary,
              items: [
                for (final id in available)
                  DropdownMenuItem<String>(value: id, child: Text(label(id))),
              ],
              onChanged: (id) {
                if (id != null) onAdd(id);
              },
            ),
          for (final id in overridden)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      label(id),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      key: ValueKey('dialect-move-$id'),
                      controller: controllers[id],
                      decoration: InputDecoration(
                        labelText: label(id),
                        // A figure of your own has no side for a %S to fill
                        // (#1023): a name holding one is not used.
                        hintText: isUserFigureKey(id)
                            ? l10n.dialectEditorUserFigureNameHint
                            : l10n.dialectEditorMoveSubHint,
                        hintMaxLines: 4,
                        errorText:
                            isUserFigureKey(id) &&
                                controllers[id]!.text.contains('%S')
                            ? l10n.dialectEditorUserFigureNameSide
                            : null,
                        errorMaxLines: 3,
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
        ],
      ),
    );
  }
}

/// What a condition in the wording [id] may test, and the words its values
/// are written with, in [dialect]: a move's, or a figure of your own's.
WordingVocabulary _wordingVocabulary(
  String id,
  Dialect dialect,
  UserFigureCatalog userFigures,
) {
  if (!isUserFigureKey(id)) {
    return _DialectEditorScreenState._renderer.moveWordingVocabulary(
      id,
      dialect,
    );
  }
  final definition =
      userFigures[id.substring(userFigureRefPrefix.length)]?.definition;
  return definition == null
      ? WordingVocabulary(const [])
      : _DialectEditorScreenState._renderer.userFigureWordingVocabulary(
          definition,
          dialect,
        );
}

/// The wording [id], typed as [text], read in [dialect]'s words: its stored
/// form, or why it can't be saved.
WordingCheck _checkWording(
  String id,
  String text,
  Dialect dialect,
  UserFigureCatalog userFigures,
) => checkWording(text.trim(), _wordingVocabulary(id, dialect, userFigures));

/// A dialect entry's label: a move's name, or, for a figure of your own's
/// `userFigure:<id>` key (#1023), the figure's name in [dialect], or a note
/// that it isn't on this device when [userFigures] lacks it.
String _entryLabel(
  String id,
  UserFigureCatalog userFigures,
  Dialect dialect,
  AppLocalizations l10n,
  FigureRenderer renderer,
) {
  if (isUserFigureKey(id)) {
    final view = userFigures[id.substring(userFigureRefPrefix.length)];
    return view == null
        ? l10n.dialectEditorUserFigureGone
        : renderer.renderFreeText(view.name, dialect);
  }
  return contraTaxonomy.moves[id]?.displayName ?? id;
}

String _branchLabel(String branch, AppLocalizations l10n) => switch (branch) {
  'inOnly' => l10n.dialectEditorMoveWordingBranchInOnly,
  'outOnly' => l10n.dialectEditorMoveWordingBranchOutOnly,
  'inAndOut' => l10n.dialectEditorMoveWordingBranchInAndOut,
  'neither' => l10n.dialectEditorMoveWordingBranchNeither,
  'singleFile' => l10n.dialectEditorMoveWordingBranchSingleFile,
  'ordinary' => l10n.dialectEditorMoveWordingBranchOrdinary,
  _ => branch,
};

/// Collapsible display-only per-move wording editor. Templates use the slots
/// shown below each field; unknown slots are rendered empty and warned about.
/// Malformed templates are blocked by the parent editor's save guard, while the
/// renderer still falls back defensively for imported or migrated data.
class _MoveWordingsEditor extends StatelessWidget {
  const _MoveWordingsEditor({
    required this.keptWording,
    required this.label,
    required this.userFigureKeys,
    required this.userFigures,
    required this.controllers,
    required this.branchControllers,
    required this.dialect,
    required this.onEdited,
    required this.onAdd,
    required this.onRemove,
    required this.onRemoveBranch,
    required this.onRestoreDefaults,
  });

  final Map<String, TextEditingController> controllers;
  final Map<String, Map<String, TextEditingController>> branchControllers;
  final Dialect dialect;
  final VoidCallback onEdited;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onRemoveBranch;
  final VoidCallback onRestoreDefaults;

  /// A move's label, or a figure of your own's name.
  final String Function(String id) label;

  /// The user's figures that can be worded (#1023), offered after the moves.
  final List<String> userFigureKeys;

  /// The user's figures, for a figure's slots and preview.
  final UserFigureCatalog userFigures;

  /// The stored form of a wording still as the editor showed it, under its
  /// [_DialectEditorScreenState._wordingKey], else null.
  final String? Function(String key, String text) keptWording;

  /// [text], the wording [id] (and [branch]) as typed, read in [dialect]'s
  /// words; one still as shown is its stored form, with nothing to report.
  WordingCheck _check(String id, String text, [String? branch]) {
    final kept = keptWording(
      _DialectEditorScreenState._wordingKey(id, branch),
      text,
    );
    if (kept != null) return WordingCheck(kept, const []);
    return checkWording(
      text.trim(),
      _wordingVocabulary(id, dialect, userFigures),
    );
  }

  static final FigureRenderer _renderer = FigureRenderer(contraTaxonomy);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final configured = controllers.keys.toList().reversed;
    final available = [
      for (final move in contraTaxonomy.moves.values)
        if (move.id != customMoveId &&
            !controllers.containsKey(move.id) &&
            !branchControllers.containsKey(move.id))
          move.id,
    ]..sort((a, b) => label(a).toLowerCase().compareTo(label(b).toLowerCase()));
    available.addAll([
      for (final key in userFigureKeys)
        if (!controllers.containsKey(key)) key,
    ]);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.dialectEditorMoveWordingsHelp,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (branchControllers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.dialectEditorMoveWordingsConditionalHelp,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.dialectEditorMoveWordingsForceHelp('{!hand}'),
              key: const ValueKey('dialect-wording-force-help'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (available.isNotEmpty)
            DropdownButton<String>(
              key: const ValueKey('dialect-add-move-wording'),
              hint: Text(
                l10n.dialectEditorAddMoveWording,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              value: null,
              isExpanded: true,
              iconEnabledColor: Theme.of(context).colorScheme.secondary,
              items: [
                for (final id in available)
                  DropdownMenuItem<String>(value: id, child: Text(label(id))),
              ],
              onChanged: (id) {
                if (id != null) onAdd(id);
              },
            ),
          for (final entry in branchControllers.entries)
            _branchWordingGroup(context, entry.key, entry.value, l10n),
          for (final id in configured) _wordingRow(context, id, l10n),
          TextButton(
            key: const ValueKey('dialect-wordings-restore'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: onRestoreDefaults,
            child: Text(l10n.dialectEditorMoveWordingsReset),
          ),
        ],
      ),
    );
  }

  Widget _wordingRow(BuildContext context, String id, AppLocalizations l10n) {
    if (isUserFigureKey(id)) return _userFigureWordingRow(context, id, l10n);
    final controller = controllers[id]!;
    final text = controller.text;
    final known = _renderer.moveWordingSlots(id);
    final used = RegExp(
      r'\{!?(\w+)\}',
    ).allMatches(text).map((match) => match[1]!).toSet();
    final unknown = used.difference(known).toList()..sort();
    final vocabulary = _wordingVocabulary(id, dialect, userFigures);
    final check = _check(id, text);
    final valid = text.trim().isEmpty || !check.hasErrors;
    final missing = valid
        ? (_renderer.moveWordingMissingSlots(id, text).toList()..sort())
        : const <String>[];
    final errorMissing = missing.where((slot) => slot != 'move').toList();
    final optionalMissing = missing.where((slot) => slot == 'move').toList();
    final previewDialect = dialect.copyWith(
      moveWordings: {...dialect.moveWordings, id: check.stored ?? ''},
    );
    final preview = _renderer.render(Figure(move: id), previewDialect);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  label(id),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              IconButton(
                key: ValueKey('dialect-wording-delete-$id'),
                icon: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                tooltip: l10n.commonRemove,
                onPressed: () => onRemove(id),
              ),
            ],
          ),
          TextField(
            key: ValueKey('dialect-wording-$id'),
            controller: controller,
            decoration: InputDecoration(
              labelText: l10n.dialectEditorMoveWordingLabel,
              hintText: _renderer.moveWordingTemplate(id),
            ),
            onChanged: (_) => onEdited(),
          ),
          Text(
            l10n.dialectEditorMoveWordingSlots(
              _renderer.moveWordingSlotLabels(id, known).join(', '),
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          WordingConditionNotes(
            vocabulary: vocabulary,
            check: check,
            errorKey: ValueKey('dialect-wording-error-$id'),
          ),
          if (unknown.isNotEmpty)
            Text(
              l10n.dialectEditorMoveWordingUnknownSlots(unknown.join(', ')),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (errorMissing.isNotEmpty)
            Text(
              l10n.dialectEditorMoveWordingMissingSlots(
                _renderer.moveWordingSlotLabels(id, errorMissing).join(', '),
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (optionalMissing.isNotEmpty)
            Text(
              l10n.dialectEditorMoveWordingOptionalSlots(
                _renderer.moveWordingSlotLabels(id, optionalMissing).join(', '),
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
            ),
          Text(
            l10n.dialectEditorMoveWordingPreview(preview),
            key: ValueKey('dialect-wording-preview-$id'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  /// A wording for one of the user's figures (#1023): its slots are the
  /// figure's own, a slot it lacks makes the figure keep its own wording, and
  /// the preview reads with its defaults. A parameter the wording leaves out
  /// is only noted, as the figure's own wording may leave one out.
  Widget _userFigureWordingRow(
    BuildContext context,
    String id,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final controller = controllers[id]!;
    final text = controller.text;
    final figureId = id.substring(userFigureRefPrefix.length);
    final definition = userFigures[figureId]?.definition;
    final known = definition?.slots ?? const <String>{};
    final used = userFigureTemplateSlots(text);
    final unknown = used.difference(known).toList()..sort();
    final vocabulary = _wordingVocabulary(id, dialect, userFigures);
    final check = _check(id, text);
    final valid = text.trim().isEmpty || !check.hasErrors;
    final tested = check.stored == null
        ? const <String>{}
        : wordingTestedNames(parseStoredWording(check.stored!) ?? const []);
    final unused = definition == null
        ? const <String>[]
        : ([
            for (final p in definition.params)
              if (!used.contains(p.key) &&
                  !used.contains(userFigureOppositeSlot(p.key)) &&
                  !tested.contains(p.key))
                p.key,
          ]..sort());
    final preview = definition == null
        ? null
        : FigureRenderer(contraTaxonomy, userFigures: userFigures).render(
            userFigureUseFigure(
              id: figureId,
              args: {
                for (final p in definition.params)
                  if (p.defaultValue != null) p.key: p.defaultValue,
              },
              text: '',
            ),
            dialect.copyWith(
              moveWordings: {...dialect.moveWordings, id: check.stored ?? ''},
            ),
          );
    String slotList(Iterable<String> slots) =>
        [for (final slot in slots) '{$slot}'].join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label(id), style: theme.textTheme.bodyMedium),
              ),
              IconButton(
                key: ValueKey('dialect-wording-delete-$id'),
                icon: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
                tooltip: l10n.commonRemove,
                onPressed: () => onRemove(id),
              ),
            ],
          ),
          TextField(
            key: ValueKey('dialect-wording-$id'),
            controller: controller,
            decoration: InputDecoration(
              labelText: l10n.dialectEditorMoveWordingLabel,
              hintText: definition == null
                  ? null
                  : wordingForEditing(definition.template, vocabulary),
            ),
            onChanged: (_) => onEdited(),
          ),
          if (definition != null)
            Text(
              l10n.dialectEditorMoveWordingSlots(
                slotList(known.toList()..sort()),
              ),
              style: theme.textTheme.bodySmall,
            ),
          WordingConditionNotes(
            vocabulary: vocabulary,
            check: check,
            errorKey: ValueKey('dialect-wording-error-$id'),
            showHelp: definition != null,
          ),
          if (unknown.isNotEmpty)
            Text(
              l10n.dialectEditorUserFigureWordingUnknownSlots(
                slotList(unknown),
              ),
              key: ValueKey('dialect-wording-unknown-$id'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          if (valid && unknown.isEmpty && unused.isNotEmpty)
            Text(
              l10n.dialectEditorMoveWordingOptionalSlots(slotList(unused)),
              style: TextStyle(color: theme.colorScheme.tertiary),
            ),
          if (preview != null)
            Text(
              l10n.dialectEditorMoveWordingPreview(preview),
              key: ValueKey('dialect-wording-preview-$id'),
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _branchWordingGroup(
    BuildContext context,
    String moveId,
    Map<String, TextEditingController> controllers,
    AppLocalizations l10n,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.dialectEditorMoveWordingsConditionalLabel(label(moveId)),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              IconButton(
                key: ValueKey('dialect-wording-delete-$moveId'),
                icon: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                tooltip: l10n.commonRemove,
                onPressed: () => onRemoveBranch(moveId),
              ),
            ],
          ),
        ),
        for (final entry in controllers.entries)
          _branchWordingRow(context, moveId, entry.key, entry.value, l10n),
      ],
    );
  }

  Widget _branchWordingRow(
    BuildContext context,
    String moveId,
    String branch,
    TextEditingController controller,
    AppLocalizations l10n,
  ) {
    final known = _renderer.moveWordingBranchSlots(moveId, branch);
    final text = controller.text;
    final hasText = text.trim().isNotEmpty;
    final vocabulary = _wordingVocabulary(moveId, dialect, userFigures);
    final check = _check(moveId, text, branch);
    final missing = hasText
        ? (_renderer
              .moveWordingBranchMissingSlots(moveId, branch, text)
              .toList()
            ..sort())
        : const <String>[];
    final previewDialect = dialect.copyWith(
      moveWordingBranches: {
        ...dialect.moveWordingBranches,
        moveId: {
          ...dialect.moveWordingBranches[moveId] ?? {},
          branch: check.stored ?? '',
        },
      },
    );
    final preview = _renderer.render(
      _branchFigure(moveId, branch),
      previewDialect,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _branchLabel(branch, l10n),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextField(
            key: ValueKey('dialect-wording-$moveId-$branch'),
            controller: controller,
            decoration: InputDecoration(
              labelText: l10n.dialectEditorMoveWordingLabel,
              hintText: _renderer.moveWordingBranchTemplate(moveId, branch),
            ),
            onChanged: (_) => onEdited(),
          ),
          Text(
            l10n.dialectEditorMoveWordingSlots(
              _renderer.moveWordingSlotLabels(moveId, known).join(', '),
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (hasText)
            WordingConditionNotes(
              vocabulary: vocabulary,
              check: check,
              errorKey: ValueKey('dialect-wording-error-$moveId-$branch'),
            ),
          if (missing.isNotEmpty)
            Text(
              l10n.dialectEditorMoveWordingMissingSlots(
                _renderer.moveWordingSlotLabels(moveId, missing).join(', '),
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Text(
            l10n.dialectEditorMoveWordingPreview(preview),
            key: ValueKey('dialect-wording-preview-$moveId-$branch'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Figure _branchFigure(String moveId, String branch) {
    switch (moveId) {
      case 'form_a_long_wave':
        return Figure(
          move: moveId,
          params: {
            'in': branch == 'inOnly' || branch == 'inAndOut',
            'out': branch == 'outOnly' || branch == 'inAndOut',
          },
        );
      case 'promenade':
      case 'circle':
        return Figure(
          move: moveId,
          params: {'singleFile': branch == 'singleFile'},
        );
      default:
        return Figure(move: moveId);
    }
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
    required this.onEdited,
    required this.onAdd,
    required this.onRemove,
  });

  final Map<String, TextEditingController> controllers;

  /// The dialect as currently edited, so a row label tracks the role terms the
  /// caller is typing (`onesRole1` reads "first lark" the moment role1 becomes
  /// "lark").
  final Dialect dialect;
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
    final overridden = controllers.keys.toList().reversed;
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
          if (available.isNotEmpty)
            DropdownButton<String>(
              key: const ValueKey('dialect-add-dancer'),
              hint: Text(
                l10n.dialectEditorAddDancerTerm,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              value: null,
              isExpanded: true,
              iconEnabledColor: Theme.of(context).colorScheme.secondary,
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
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
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
      params: const {'who': 'role1s', 'hand': 'left', 'travel': 1.5},
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
