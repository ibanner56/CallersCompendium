import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../editor/pending_move_text_controller.dart';
import 'responsive_autocomplete.dart';

/// The kind of entry selected from a [MoveAutocomplete]: a taxonomy move or
/// alias, the structural modifier or sequence, or one of the user's own
/// figures, a
/// compound (#709) or a new figure (#1023), whose [MoveOption.id] is its
/// glossary entry id.
enum MoveOptionKind { move, modifier, sequence, compound, userFigure }

/// One selectable entry in a [MoveAutocomplete]: either a canonical move, an
/// alias, or an enabled structural option. [id] is what gets stored on the
/// figure/query (a move id, an alias id, or a structural move id), so aliases
/// keep their own identity (a "see saw" stays a see saw).
class MoveOption {
  const MoveOption({
    required this.id,
    required this.displayName,
    this.kind = MoveOptionKind.move,
    this.searchTerms = const [],
  });

  final String id;
  final String displayName;
  final MoveOptionKind kind;

  /// One of the user's own figures, listed first and marked as theirs.
  bool get isUsers =>
      kind == MoveOptionKind.compound || kind == MoveOptionKind.userFigure;

  /// Other words that find one of the user's own figures: its keywords.
  final List<String> searchTerms;
}

/// A keyboard-first type-ahead move picker over a [Taxonomy]'s moves (and,
/// optionally, aliases). Typing `sw` offers swing; selecting an option reports
/// it via [onSelected]. Factored out of the search query builder so the dance
/// editor and the "has figure" search row share one move picker
/// (`docs/design/ux.md` §3).
class MoveAutocomplete extends StatefulWidget {
  const MoveAutocomplete({
    super.key,
    required this.taxonomy,
    required this.initialText,
    required this.onSelected,
    this.dialect,
    this.fieldKey,
    this.onCleared,
    this.onCustomSubmitted,
    this.submitsAsText,
    this.commitOnBlur = false,
    this.includeAliases = true,
    this.includeModifier = false,
    this.includeSequence = false,
    this.compoundOptions = const [],
    this.compoundMarkerLabel = 'custom',
    this.includeCustomMove = true,
    this.modifierOptionLabel = 'modifier',
    this.sequenceOptionLabel = 'sequence',
    this.hintText = 'e.g. swing',
    this.labelText = 'Move',
    this.autofocus = false,
  });

  final Taxonomy taxonomy;

  /// Active dialect. When non-null (and non-canonical), option labels and the
  /// resting field text render via the dialect's move substitutions and typing
  /// matches those dialect terms too (e.g. a custom "buzz" for `swing` both
  /// displays and is searchable). Null falls back to canonical taxonomy names.
  final Dialect? dialect;

  /// Text shown in the field (e.g. the current move's display name). Changes
  /// after mount update the field when it owns its controller.
  final String initialText;

  /// Called when the user picks a move/alias from the options.
  final ValueChanged<MoveOption> onSelected;

  /// Optional key stem for the inner [TextField] (`<fieldKey>-input`).
  final String? fieldKey;

  /// Called when the field is emptied (clears the current move).
  final VoidCallback? onCleared;

  /// Called when the user submits free text that matches no move — the hook the
  /// editor uses to spin up a custom figure. Null disables custom entry.
  final ValueChanged<String>? onCustomSubmitted;

  /// Whether Enter on this text goes to [onCustomSubmitted] even though it
  /// matches an option by part of a name: the editor's shorthand tokens, so
  /// `rl` reaches the user's shorthand rather than butterfly whirl. Such text
  /// is offered no options. An option named exactly by the text still wins.
  /// Null treats no text that way.
  final bool Function(String text)? submitsAsText;

  /// Whether leaving the box settles what was typed in it without Enter
  /// (AUTH-1): an option named exactly by the text is chosen, text that
  /// [submitsAsText] takes goes to [onCustomSubmitted], and anything else is
  /// put back to [initialText]. On a phone, closing the options sheet without
  /// choosing settles the sheet's text the same way.
  ///
  /// A [PendingMoveTextScope] above the box is told whether it holds text
  /// leaving would apply, and can settle it, so Save and Back do not depend on
  /// the tap moving focus. Off by default: a picker whose choice closes a
  /// dialog, or runs a search, must not act because focus moved.
  final bool commitOnBlur;

  final bool includeAliases;

  /// Whether to offer the structural `modifier` option alongside taxonomy
  /// moves. Callers that enable this must handle [MoveOptionKind.modifier] by
  /// creating a container draft rather than storing [modifierMove] as a
  /// leaf move.
  final bool includeModifier;

  /// Whether to offer the structural `sequence` option. As for
  /// [includeModifier], a caller that enables it must handle
  /// [MoveOptionKind.sequence] by creating a container draft.
  final bool includeSequence;

  /// The user's own figures to offer: combinations (#709), each a
  /// [MoveOptionKind.compound] option, and new figures (#1023), each a
  /// [MoveOptionKind.userFigure] option. Matching ones are listed before
  /// every move, within the same cap. Empty (the default) offers none.
  final List<MoveOption> compoundOptions;

  /// What marks one of [compoundOptions] as the user's own, in words.
  final String compoundMarkerLabel;

  /// Whether the taxonomy's own [customMove] is offered. An editor that
  /// cannot hold a custom figure turns it off, as it turns off
  /// [onCustomSubmitted].
  final bool includeCustomMove;

  /// Label shown for the optional structural modifier entry.
  final String modifierOptionLabel;

  /// Label shown for the optional structural sequence entry.
  final String sequenceOptionLabel;

  final String hintText;
  final String labelText;
  final bool autofocus;

  @override
  State<MoveAutocomplete> createState() => _MoveAutocompleteState();
}

class _MoveAutocompleteState extends State<MoveAutocomplete> {
  static String _labelKey(String label) => label.trim().toLowerCase();

  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  final FocusNode _focusNode = FocusNode();

  /// The scope's controller this box attached to when it took focus, while
  /// [MoveAutocomplete.commitOnBlur] is on.
  PendingMoveTextController? _pending;

  /// The box's text, as [_labelKey], when it last showed what the row holds:
  /// [MoveAutocomplete.initialText], or what Enter or a choice just applied.
  /// Enter takes focus from the box before the row's new move reaches
  /// [MoveAutocomplete.initialText], and that blur must not apply it again.
  late String _settledKey = _labelKey(widget.initialText);

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    _controller.addListener(_reportPendingText);
  }

  @override
  void didUpdateWidget(MoveAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The row's move changed (chosen here, or by Undo, a restore or a
    // reorder): show it.
    if (oldWidget.initialText != widget.initialText) {
      _controller.value = TextEditingValue(text: widget.initialText);
      _settledKey = _labelKey(widget.initialText);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.removeListener(_reportPendingText);
    _pending?.detach(_settle);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!widget.commitOnBlur) return;
    if (_focusNode.hasFocus) {
      _pending = PendingMoveTextScope.maybeOf(context)?..attach(_settle);
      _reportPendingText();
    } else {
      // On a phone the field gives up focus when it opens the options sheet;
      // its text is still the row's then, so settling changes nothing.
      _settle();
    }
  }

  /// Settles the box as leaving it does. A box that has lost focus stops
  /// serving the scope; one the scope settled while it still has focus (Save
  /// on a touch screen, which can leave focus in the box) keeps serving it.
  void _settle() {
    if (!mounted) return;
    final text = _controller.text;
    if (!_isSettled(text) && !_applyOnBlur(text)) {
      // The box can keep focus (Save on a touch screen), so the caret goes
      // somewhere valid: the end, as after a choice.
      _controller.value = TextEditingValue(
        text: widget.initialText,
        selection: TextSelection.collapsed(offset: widget.initialText.length),
      );
      _settledKey = _labelKey(widget.initialText);
    }
    if (_focusNode.hasFocus) {
      _reportPendingText();
    } else {
      final pending = _pending;
      _pending = null;
      pending?.detach(_settle);
    }
  }

  /// Settles text typed into the phone sheet and left without a choice: the
  /// field under the sheet still shows the row, so text that applies nothing
  /// is simply dropped.
  void _settleSheetText(String text) {
    if (mounted && !_isSettled(text)) _applyOnBlur(text);
  }

  /// Whether [text] is what the row holds already, or blank: emptying the box
  /// has cleared the move ([MoveAutocomplete.onCleared]).
  bool _isSettled(String text) {
    final q = _labelKey(text);
    return q.isEmpty || q == _settledKey || q == _labelKey(widget.initialText);
  }

  void _select(MoveOption option) {
    _settledKey = _labelKey(option.displayName);
    widget.onSelected(option);
  }

  void _reportPendingText() {
    _pending?.updatePendingText(
      _focusNode.hasFocus &&
          !_isSettled(_controller.text) &&
          _blurAction(_controller.text) != null,
    );
  }

  /// What leaving the box with [text] in it applies, or null when it puts the
  /// row's own text back (AUTH-1): the option [text] names exactly, as Enter
  /// would choose it; else, when [text] is a shorthand
  /// ([MoveAutocomplete.submitsAsText]), [text] itself, for
  /// [MoveAutocomplete.onCustomSubmitted]. Unlike Enter it never takes a
  /// suggestion by part of a name, or makes a custom figure.
  Object? _blurAction(String text) {
    final q = _labelKey(text);
    for (final option in _matchingOptions(q)) {
      if (_namesExactly(option, q)) return option;
    }
    if (widget.onCustomSubmitted != null &&
        (widget.submitsAsText?.call(q) ?? false)) {
      return text.trim();
    }
    return null;
  }

  /// Applies what leaving the box with [text] in it applies, and returns
  /// whether there was anything.
  bool _applyOnBlur(String text) {
    switch (_blurAction(text)) {
      case final MoveOption option:
        // As choosing it from the options does: the box shows its name.
        _controller.value = TextEditingValue(
          text: option.displayName,
          selection: TextSelection.collapsed(offset: option.displayName.length),
        );
        _select(option);
        return true;
      case final String shorthand:
        _settledKey = _labelKey(shorthand);
        widget.onCustomSubmitted?.call(shorthand);
        return true;
    }
    return false;
  }

  /// The options offered for [query], first the one Enter takes (AUTH-8):
  /// the option named exactly by it (`star` is star, not star through, and
  /// `hey` is the app's hey, not your "Hey with a twist"); else, when it is a
  /// shorthand ([MoveAutocomplete.submitsAsText]), none, so Enter sends it to
  /// [MoveAutocomplete.onCustomSubmitted]; else every option it finds, in
  /// their usual order.
  List<MoveOption> _optionsFor(String query) {
    final q = _labelKey(query);
    final options = _matchingOptions(q);
    final exact = options.indexWhere((o) => _namesExactly(o, q));
    if (exact > 0) {
      options.insert(0, options.removeAt(exact));
    } else if (exact == -1 && (widget.submitsAsText?.call(q) ?? false)) {
      return const [];
    }
    return options.take(8).toList();
  }

  /// Every option [query] finds, in the order they are offered.
  List<MoveOption> _matchingOptions(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final dialect = widget.dialect ?? Dialect.canonical;
    final renderer = FigureRenderer(widget.taxonomy);
    // Match on canonical name, id, keywords, AND the dialect display term so a
    // user can type a custom substitution (e.g. "buzz" for swing).
    bool matches(
      String id,
      String displayName,
      String dialectName,
      List<String> keywords,
    ) {
      return displayName.toLowerCase().contains(q) ||
          dialectName.toLowerCase().contains(q) ||
          id.toLowerCase().contains(q) ||
          keywords.any((k) => k.toLowerCase().contains(q));
    }

    final options = <MoveOption>[
      for (final c in widget.compoundOptions)
        if (c.displayName.toLowerCase().contains(q) ||
            c.searchTerms.any((k) => k.toLowerCase().contains(q)))
          c,
      if (widget.includeModifier &&
          matches(
            modifierMove,
            widget.modifierOptionLabel,
            widget.modifierOptionLabel,
            const [],
          ))
        MoveOption(
          id: modifierMove,
          displayName: widget.modifierOptionLabel,
          kind: MoveOptionKind.modifier,
        ),
      if (widget.includeSequence &&
          matches(
            sequenceMove,
            widget.sequenceOptionLabel,
            widget.sequenceOptionLabel,
            const [],
          ))
        MoveOption(
          id: sequenceMove,
          displayName: widget.sequenceOptionLabel,
          kind: MoveOptionKind.sequence,
        ),
      for (final m in widget.taxonomy.moves.values)
        if ((widget.includeCustomMove || m.id != customMove) &&
            matches(
              m.id,
              m.displayName,
              renderer.displayMoveName(m.id, dialect),
              m.searchKeywords,
            ))
          MoveOption(
            id: m.id,
            displayName: renderer.displayMoveName(m.id, dialect),
          ),
    ];
    if (widget.includeAliases) {
      // An alias whose label equals one already offered (the v34 "pull by"
      // aliases all read "pull by") is indistinguishable in the list, so it
      // only costs a slot and invites a coin-flip. Drop it; the move, or the
      // earlier alias, already covers that label. Moves are never dropped, so
      // a dialect that gives two moves one term cannot hide either of them.
      final labels = {
        for (final o in options)
          if (!o.isUsers) _labelKey(o.displayName),
      };
      for (final a in widget.taxonomy.aliases.values) {
        final label = renderer.displayMoveName(a.id, dialect);
        if (matches(a.id, a.displayName, label, a.searchKeywords) &&
            labels.add(_labelKey(label))) {
          options.add(MoveOption(id: a.id, displayName: label));
        }
      }
    }
    return options;
  }

  /// Whether [option] is named [q]: its label, or for a move or alias, its
  /// own name or its id with spaces.
  bool _namesExactly(MoveOption option, String q) {
    if (_labelKey(option.displayName) == q) return true;
    if (option.kind != MoveOptionKind.move) return false;
    final name =
        widget.taxonomy.moves[option.id]?.displayName ??
        widget.taxonomy.aliases[option.id]?.displayName;
    return (name != null && _labelKey(name) == q) ||
        option.id.replaceAll('_', ' ') == q;
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveAutocomplete<MoveOption>(
      textEditingController: _controller,
      focusNode: _focusNode,
      displayStringForOption: (o) => o.displayName,
      // Reuses the field's own label as the sheet's a11y announcement (e.g.
      // "Move") — matches the field the user was just interacting with,
      // rather than introducing a separate string.
      sheetSemanticLabel: widget.labelText,
      autofocus: widget.autofocus,
      overlayConstraints: const BoxConstraints(maxHeight: 240, maxWidth: 280),
      optionsBuilder: (value) => _optionsFor(value.text),
      onSelected: _select,
      onSheetDismissed: widget.commitOnBlur ? _settleSheetText : null,
      optionTileBuilder: (context, option, onSelected) {
        final compound = option.isUsers;
        return ListTile(
          key: ValueKey(
            '${widget.fieldKey ?? 'move'}-option-'
            '${switch (option.kind) {
              MoveOptionKind.compound => 'compound:',
              MoveOptionKind.userFigure => 'userFigure:',
              _ => '',
            }}${option.id}',
          ),
          dense: true,
          title: Text(option.displayName),
          // Marked in words for assistive technology, not by the icon alone.
          trailing: compound
              ? Tooltip(
                  message: widget.compoundMarkerLabel,
                  // The icon's own label says it; read once.
                  excludeFromSemantics: true,
                  child: Icon(
                    Icons.person_outline,
                    size: 18,
                    semanticLabel: widget.compoundMarkerLabel,
                  ),
                )
              : null,
          onTap: onSelected,
        );
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit, autofocus) {
        return TextField(
          key: widget.fieldKey == null
              ? null
              : ValueKey('${widget.fieldKey}-input'),
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (text) {
            if (text.trim().isEmpty) widget.onCleared?.call();
          },
          onSubmitted: (text) {
            final q = text.trim();
            final options = _optionsFor(q);
            final custom = widget.onCustomSubmitted;
            final applied =
                options.isNotEmpty || (q.isNotEmpty && custom != null);
            if (options.isNotEmpty) {
              _select(options.first);
            } else if (q.isNotEmpty) {
              custom?.call(q);
            }
            onSubmit();
            // Enter takes focus from the box next; what it just applied is
            // the row's now, not text for that blur to apply again. Text it
            // applied nothing for is still put back. (The phone sheet's own
            // field closes the sheet instead.)
            if (applied && identical(controller, _controller)) {
              _settledKey = _labelKey(controller.text);
            }
          },
        );
      },
    );
  }
}
